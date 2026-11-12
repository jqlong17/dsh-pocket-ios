// 发送、实时帧和 RPC

import SwiftUI
import Security
import Textual
import DSHKit
import VisionKit
import AVFoundation
import Observation
import PhotosUI
import UIKit
import Photos
import os
import AudioToolbox
import ImageIO
import UserNotifications

extension ConnectionModel {

    static func prepareImage(_ image: UIImage) -> PocketDraftImage? {
        let maxSide: CGFloat = 2048
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return nil }
        return PocketDraftImage(data: data, mediaType: "image/jpeg",
                                name: "photo-\(Int(Date().timeIntervalSince1970)).jpg", uiImage: resized)
    }

    @MainActor
    func pollForReply(_ session: PocketSession, after text: String, afterSequence: Int) async {
        let started = Date()
        timingLog("history_poll_start text=\(text.debugDescription)")
        for _ in 0..<LiveStreamPolicy.historyPollAttempts {
            if Task.isCancelled { return }
            try? await Task.sleep(for: LiveStreamPolicy.historyPollInterval)
            if Task.isCancelled { return }
            guard selectedSession?.sessionId == session.sessionId else { return }
            // 实时 follow 已经把回复送到时就不必再轮询分页了；轮询只作为断流兜底。
            if messages.contains(where: { !$0.isUser && !$0.isPending && $0.sequence > afterSequence }) {
                timingLog("reply_available source=follow total_elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                return
            }
            do {
                let address: [String: Any] = ["kind": "session", "sessionId": session.sessionId]
                let page = try await rpcClient.rpcAdapted("session/page", args: ["request": ["address": address, "maxMessages": Self.conversationMessageLimit]])
                // await 期间可能已切换会话，返回后必须再校验，否则旧会话消息会串进当前会话。
                guard !Task.isCancelled,
                      activeConversation?.sessionId == session.sessionId,
                      selectedSession?.sessionId == session.sessionId else { return }
                let records = page["records"] as? [[String: Any]] ?? []
                let incoming = records.compactMap(PocketMessage.init(record:))
                timingLog("history_poll_result messages=\(incoming.count) elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                mergeMessages(incoming)
                mergeSteps(from: records)
                confirmInboxOutbox(in: records)
                if let reply = incoming.first(where: { !$0.isUser && !$0.isPending && $0.sequence > afterSequence }) {
                    timingLog("reply_available source=history seq=\(reply.sequence) chars=\(reply.text.count) total_elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                    recordDiagnostic("历史轮询找到本次助手回复，等待 \(Int(Date().timeIntervalSince(started) * 1000)) 毫秒；内容：\(reply.text)")
                    return
                }
            } catch { }
        }
        recordDiagnostic("历史轮询超时：30 次内未找到本次助手回复")
    }

    @MainActor
    func follow(_ session: PocketSession) async {
        if isDemoMode { return }
        defer {
            if activeConversation?.sessionId == session.sessionId {
                activeConversation?.isFollowing = false
            }
        }
        guard let base = URL(string: serverAddress),
              let socketURL = Self.webSocketURL(from: base, path: "api/remote.mux") else {
            recordDiagnostic("实时连接未启动：地址无效 \(serverAddress.debugDescription)")
            return
        }
        activeConversation?.isFollowing = true
        var retryDelay: Duration = LiveStreamPolicy.initialReconnectDelay
        var retryCount = 0
        var receivedSnapshot = false
        var usedHistoryFallback = false
        while !Task.isCancelled,
              activeConversation?.sessionId == session.sessionId,
              selectedSession?.sessionId == session.sessionId {
            liveConnection = .connecting
            let socket = URLSession.shared.webSocketTask(with: socketURL)
            socket.resume()
            recordDiagnostic("实时连接：发起连接")
            pocketLogger.info("follow connecting session=\(session.sessionId, privacy: .public) url=\(socketURL.absoluteString, privacy: .private)")
            let streamId = UUID().uuidString
            let open = StreamOpen(type: "open", streamId: streamId, endpoint: "session/follow", payload: ["args": ["request": ["address": ["kind": "session", "sessionId": session.sessionId], "maxMessages": Self.conversationMessageLimit]]])
            do {
                let data = try JSONEncoder().encode(open)
                guard let text = String(data: data, encoding: .utf8) else { throw ConnectionError.invalidPayload }
                try await socket.send(.string(text))
                let heartbeat = Task {
                    while !Task.isCancelled {
                        do {
                            try await Task.sleep(for: LiveStreamPolicy.heartbeatInterval)
                            try await sendPing(socket)
                        } catch {
                            if !Task.isCancelled { socket.cancel(with: .abnormalClosure, reason: nil) }
                            return
                        }
                    }
                }
                defer { heartbeat.cancel() }
                while !Task.isCancelled {
                    let frame: URLSessionWebSocketTask.Message
                    if isTurnRunning {
                        // 生成中理应持续有事件；25 秒没有任何帧说明连接假死（常见于公网隧道），主动断开重连。
                        frame = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
                            group.addTask {
                                try await withTaskCancellationHandler {
                                    try await socket.receive()
                                } onCancel: {
                                    socket.cancel(with: .goingAway, reason: nil)
                                }
                            }
                            group.addTask {
                                try await Task.sleep(for: LiveStreamPolicy.runningIdleTimeout)
                                throw ConnectionError.remote("生成中 \(LiveStreamPolicy.runningIdleTimeout) 无实时数据，主动重连")
                            }
                            guard let first = try await group.next() else {
                                throw ConnectionError.remote("实时连接无数据")
                            }
                            group.cancelAll()
                            return first
                        }
                    } else {
                        frame = try await withTaskCancellationHandler {
                            try await socket.receive()
                        } onCancel: {
                            socket.cancel(with: .goingAway, reason: nil)
                        }
                    }
                    let data: Data
                    switch frame {
                    case .data(let received): data = received
                    case .string(let text): data = Data(text.utf8)
                    @unknown default: continue
                    }
                    // 只解析一次：原先 guard 里解一次、调试日志里又解三次，
                    // 实时流高频时纯属浪费 CPU（每帧 4 次 JSONSerialization）。
                    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    guard let object, let value = StreamFrames.itemValue(object, streamId: streamId) else {
                        NSLog("DSH_DIAG ignored frame type=%@ streamMatch=%@",
                              object?["type"] as? String ?? "nil",
                              (object?["streamId"] as? String) == streamId ? "yes" : "no")
                        continue
                    }
                    let valueType = value["type"] as? String ?? "未知"
                    if valueType == "snapshot" { receivedSnapshot = true }
                    liveConnection = .connected
                    if conversationError?.hasPrefix("实时连接") == true { conversationError = nil }
                    // 实时流一恢复就把各会话的断网暂存一并补发。
                    flushQueuedSends()
                    retryDelay = .seconds(1)
                    pocketLogger.info("follow item valueType=\(valueType, privacy: .public) keys=\(value.keys.sorted().joined(separator: ","), privacy: .public)")
                    acceptLive(value, sessionId: session.sessionId)
                }
                if !Task.isCancelled { throw ConnectionError.remote("实时连接已结束") }
            } catch {
                socket.cancel(with: .goingAway, reason: nil)
                guard !Task.isCancelled else { break }
                liveConnection = .reconnecting(attempt: retryCount)
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
                conversationError = "实时连接中断，正在重连：\(error.localizedDescription)"
                recordDiagnostic("实时连接中断，\(Int(retryDelay.components.seconds)) 秒后重试：\(error.localizedDescription)")
                pocketLogger.error("follow failed: \(error.localizedDescription, privacy: .public)")
                if !receivedSnapshot && !usedHistoryFallback {
                    usedHistoryFallback = true
                    await loadHistory(session)
                }
                // 重连多次仍失败时探测登录态：DSH 重启后 browser-auth cookie 会失效，
                // WS 只会一直重连，必须回到连接页重新输入密码。
                if retryCount >= 1 {
                    do {
                        _ = try await fetchSessions()
                    } catch let authError as ConnectionError {
                        if authError.isUnauthorized {
                            handleAuthExpired()
                            return
                        }
                    } catch { /* 其他网络错误继续重连 */ }
                }
                do { try await Task.sleep(for: retryDelay) } catch { break }
                retryDelay = min(retryDelay * 2, .seconds(15))
                retryCount += 1
            }
        }
        if selectedSession?.sessionId == session.sessionId { liveConnection = .disconnected(reason: nil) }
    }

    @MainActor
    /// 帧处理实现在 LiveFrameApplier（依赖闭包注入）；这里只转发。
    func acceptLive(_ value: [String: Any], sessionId: String) {
        liveFrameApplier.accept(value, sessionId: sessionId)
    }

    /// 装配实时帧处理的依赖（幂等）。
    @MainActor
    func installLiveFrameProviders() {
        guard liveFrameApplier.providers == nil else { return }
        liveFrameApplier.providers = LiveFrameApplier.Providers(
            isCurrentSession: { [weak self] sessionId in
                self?.activeConversation?.sessionId == sessionId
                    && self?.selectedSession?.sessionId == sessionId
            },
            markFrameArrived: { @MainActor [weak self] in self?.lastLiveFrameAt = Date() },
            mergeMessages: { @MainActor [weak self] messages in self?.mergeMessages(messages) },
            mergeSteps: { @MainActor [weak self] records in self?.mergeSteps(from: records) },
            confirmInboxOutbox: { @MainActor [weak self] records in self?.confirmInboxOutbox(in: records) },
            messages: { [weak self] in self?.messages ?? [] },
            replaceMessages: { @MainActor [weak self] list in self?.messages = list },
            confirmOutbox: { @MainActor [weak self] ids in self?.confirmOutbox(rpcIds: ids) },
            markAccepted: { _ in },
            removeAcked: { @MainActor [weak self] ids in self?.ackedSendRpcIds.subtract(ids) },
            removeFailed: { @MainActor [weak self] ids in self?.failedSendRpcIds.subtract(ids) },
            clearConversationError: { @MainActor [weak self] in self?.conversationError = nil },
            applyStepEvent: { @MainActor [weak self] event in self?.applyStepEvent(event) },
            finishLoading: { @MainActor [weak self] source in
                guard let self, let conversation = self.activeConversation else { return }
                self.noteLoadFinished(source: source, conversation: conversation)
            },
            setLoadingConversation: { @MainActor [weak self] value in self?.isLoadingConversation = value },
            requestScrollToBottom: { @MainActor [weak self] in self?.requestScrollToBottom() },
            record: { @MainActor [weak self] message in self?.recordDiagnostic(message) },
            log: { message in pocketLogger.info("\(message, privacy: .public)") },
            timing: { message in timingLog(message) }
        )
    }


    func sendPing(_ socket: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.sendPing { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    /// 登录失效（DSH 重启导致 cookie 失效 / 密码被改）：回到连接页并要求重新输入密码。
    @MainActor
    func handleAuthExpired() {
        guard !isDemoMode else { return }
        // DSH 重启后 session cookie 会失效，但设备凭证还在：
        // 先用它静默换一张新票，成功就直接重连，用户看不到任何提示。
        if !authRefreshAttempted, ConnectionVault.loadDeviceToken() != nil {
            authRefreshAttempted = true
            Task { @MainActor in
                if await self.tryRefreshAuth() {
                    self.recordDiagnostic("设备凭证换票成功，自动重连")
                    await self.connect()
                    return
                }
                self.finishAuthExpired()
            }
            return
        }
        finishAuthExpired()
    }

    /// 用长期设备凭证向插件换新的 `dsh-auth` cookie（跟随 302 即种上）。
    @MainActor
    func tryRefreshAuth() async -> Bool {
        guard let token = ConnectionVault.loadDeviceToken(),
              let base = try? Self.serverURL(from: serverAddress) else { return false }
        // 先删掉已失效的 dsh-auth cookie：带着旧凭证去换票，DSH 会当成「续期一个失效会话」，
        // 结果立刻又 401（实测：换票后 2 秒再次失效）。
        purgeAuthCookies(for: base)
        var request = URLRequest(url: base.appending(path: "dsh-pocket-ios/refresh"))
        request.httpMethod = "POST"
        // 插件会解析 body：不带 body 会得到 bad-request（HTTP 200 + ok:false），
        // 而旧 cookie 还在时又会被误判成换票成功。
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "x-dsh-pocket-device")
        request.timeoutInterval = 10
        request.httpShouldHandleCookies = true
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            recordDiagnostic("设备凭证换票失败：请求未成功")
            return false
        }
        // 必须是新换到的 cookie：请求前已清空旧 cookie，这里能查到就是新的。
        let fresh = HTTPCookieStorage.shared.cookies(for: base)?
            .contains { $0.name.hasPrefix("dsh-auth") } ?? false
        if fresh {
            ConnectionVault.saveAuthCookies(from: base)
            return true
        }
        // 没拿到 cookie：把插件返回的 ok:false 说明记下来，便于排查。
        let snippet = String(data: data.prefix(120), encoding: .utf8) ?? ""
        recordDiagnostic("设备凭证换票失败：未拿到新 cookie（\(snippet)）")
        return false
    }

    /// 删掉 HTTPCookieStorage 里的认证 cookie（只删 dsh-auth 开头，不动设备凭证与其它 cookie）。
    @MainActor
    func purgeAuthCookies(for url: URL) {
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        for cookie in cookies where cookie.name.hasPrefix("dsh-auth") {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    /// 真正失效：清理并提示用户重新配对。
    @MainActor
    func finishAuthExpired() {
        recordDiagnostic("登录已过期且设备凭证不可用：返回连接页")
        isConnected = false
        pin = ""
        PinKeychain.clear()
        // cookie 已失效：清掉，避免下次启动拿着废凭证反复 401。
        // 地址保留，用户重新输入密码/扫码即可，不必重新找电脑。
        ConnectionVault.clearAuthCookies()
        if let base = try? Self.serverURL(from: serverAddress) { purgeAuthCookies(for: base) }
        selectedSession = nil
        navigationPath = []
        activeConversation?.liveTask?.cancel()
        liveConnection = .disconnected(reason: "auth")
        errorMessage = L10n.t("登录已过期（DSH 可能重启过），请重新扫码配对或输入访问密码。")
    }

    /// 发送按钮入口：先确认当前打开的就是这个会话，避免消息发到别的 session。
    @MainActor
    func sendMessage(in session: PocketSession) {
        if selectedSession?.sessionId != session.sessionId {
            recordDiagnostic("发送前纠正会话：期望 \(session.displayTitle)")
            selectedSession = session
            open(session)
            // 继续发送，避免"点了发送但输入框内容还在、也没发出去"。
            sendMessage()
            return
        }
        sendMessage()
    }

    @MainActor
    func sendMessage() {
        if isSending {
            recordDiagnostic("发送被忽略：上一条仍在发送中")
            return
        }
        if isDemoMode {
            // sendDemoMessage 自己会清空草稿；这里不能先清，否则它读不到文本。
            sendTask = Task { await self.sendDemoMessage() }
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = draftImages
        guard (!text.isEmpty || !attachments.isEmpty), selectedSession != nil else {
            recordDiagnostic("发送被忽略：文本为空或未打开会话")
            return
        }
        sendTask?.cancel()
        // 有引用时把原文作为 Markdown 引用块前置（DSH 协议层只接受文本/图片块）。
        var outgoingText = text
        if let quote = pendingQuote {
            outgoingText = quotedPrefix(for: quote) + text
            recordDiagnostic("发送带引用：引用 #\(quote.sequence)")
            pendingQuote = nil
        }
        // 立刻清空：不等异步 performSend 的 guard，也避免中文输入法把 marked text 留在框里。
        clearDraftImmediately()
        sendTask = Task { await self.performSend(text: outgoingText, attachments: attachments) }
    }

    /// 同步清空当前输入框 + 该会话的持久化草稿；下一轮 runloop 再清一次，兜住输入法回填。
    @MainActor
    func clearDraftImmediately() {
        let conversation = activeConversation
        let sessionId = conversation?.sessionId ?? selectedSession?.sessionId
        conversation?.draft = ""
        conversation?.draftImages = []
        draft = ""
        draftImages = []
        if let sessionId { DraftStore.save("", for: sessionId) }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.activeConversation === conversation || conversation == nil {
                self.draft = ""
                self.draftImages = []
            }
        }
    }

    /// 取消"发送中"的消息：撤回本地待确认气泡，恢复输入内容。
    @MainActor
    func cancelSend() {
        guard isSending else { return }
        sendTask?.cancel()
        sendTask = nil
        if let id = pendingSendID { messages.removeAll { $0.id == id } }
        if let rpcId = pendingSendRpcId {
            removeOutbox(rpcIds: [rpcId])
            ackedSendRpcIds.remove(rpcId)
            failedSendRpcIds.remove(rpcId)
        }
        pendingSendID = nil
        pendingSendRpcId = nil
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft = cancelledDraft
            draftImages = cancelledImages
        }
        cancelledDraft = ""
        cancelledImages = []
        isSending = false
        conversationError = nil
        recordDiagnostic("已取消发送")
    }

    @MainActor
    func startCoordinator(for conversation: ConversationState, session: PocketSession,
                          client: DSHClient, showsLoading: Bool) {
        conversation.coordinatorTask?.cancel()
        if let old = conversation.coordinator { Task { await old.stop() } }
        let config = SyncConfig(maxMessages: Self.conversationMessageLimit,
                                watchdog: .seconds(25),
                                baseBackoff: .seconds(1),
                                maxBackoff: .seconds(15),
                                // 会话内容已经在内存里（再次进入）就不必再拉一次整页，只靠 WS 快照补齐。
                                fetchHTTPBaseline: SessionOpenPolicy.shouldFetchHTTPBaseline(
                                    cachedMessageCount: conversation.messages.count))
        let coordinator = SessionSyncCoordinator(sessionId: session.sessionId, transport: client, config: config)
        conversation.coordinator = coordinator
        conversation.coordinatorStarted = true
        // 有缓存时不要再把「加载中」打开，也不要重置计时（那会把 cache 来源覆盖成 snapshot）。
        if showsLoading {
            conversation.isLoadingConversation = true
            conversation.loadStartedAt = Date()
            conversation.loadTimingPending = true
        }
        let updates = coordinator.updates
        conversation.coordinatorTask = Task { [weak self] in
            for await update in updates {
                if Task.isCancelled { break }
                await self?.applyCoordinatorUpdate(update, conversation: conversation)
            }
        }
        Task { await coordinator.start() }
    }

    /// 请求更早一页历史（滚动到顶部附近时调用）。
    @MainActor
    func loadOlderMessages() {
        guard !isDemoMode, !isLoadingOlder, hasMoreOlder,
              let coordinator = activeConversation?.coordinator,
              let oldest = messages.min(by: { $0.sequence < $1.sequence }) else { return }
        isLoadingOlder = true
        olderAnchorID = oldest.id
        recordDiagnostic("请求更早历史：beforeSeq=\(oldest.sequence)")
        Task { await coordinator.loadOlder() }
    }

    @MainActor
    func applyCoordinatorUpdate(_ update: SessionUpdate, conversation: ConversationState) async {
        guard activeConversation === conversation else { return }
        switch update {
        case .connection(let state):
            liveConnection = Self.appConnectionState(from: state)
            if case .connected = state { conversationError = nil }
        case .snapshot(let dshMessages, let dshSteps, let hasMore):
            mergeMessages(dshMessages.map(Self.pocketMessage(from:)))
            for step in dshSteps { applyDSHStep(step, historical: true) }
            hasMoreOlder = hasMore
            isLoadingConversation = false
            noteLoadFinished(source: "snapshot", conversation: conversation)
        case .messages(let dshMessages):
            mergeMessages(dshMessages.map(Self.pocketMessage(from:)))
            isLoadingConversation = false
            if isLoadingOlder {
                isLoadingOlder = false
                olderLoadTick += 1
            }
        case .hasMore(let more):
            hasMoreOlder = more
            if isLoadingOlder {
                isLoadingOlder = false
                olderLoadTick += 1
            }
            recordDiagnostic("历史分页：\(more ? "还有更早消息" : "已到最早")")
        case .step(let step):
            applyDSHStep(step)
        case .title(_, let title):
            updateSessionTitle(title)
        case .assistantDelta:
            break
        }
    }

    @MainActor
    func applyDSHStep(_ step: DSHStepEvent, historical: Bool = false, storeBodies: Bool = false) {
        switch step {
        case .toolCall(let sequence, let turn, let callId, let name, let detail, let arguments):
            if !steps.contains(where: { $0.id == callId }) {
                steps.append(PocketStep(id: callId, sequence: sequence, turn: turn, number: 0,
                                        name: name, detail: detail))
                steps.sort { $0.sequence < $1.sequence }
                recordDiagnostic("过程：\(name)\(detail.isEmpty ? "" : "（\(detail)）")")
            }
            if name == "ask_user_question" {
                noteQuestionAsked(callId: callId, turn: turn, arguments: arguments)
            }
        case .toolResult(_, _, let callId, let text, let isError, let images):
            if let index = steps.firstIndex(where: { $0.id == callId }) {
                steps[index].isError = isError
                steps[index].finished = true
                guard storeBodies else { break }
                steps[index].resultText = text
                steps[index].detailsLoaded = true
                if !images.isEmpty {
                    recordDiagnostic("工具结果包含图片：\(images.count) 张")
                    steps[index].images = images.map {
                        PocketImageRef(attachmentId: $0.attachmentId,
                                       mediaType: $0.mediaType,
                                       bytes: $0.bytes ?? 0,
                                       width: $0.width,
                                       height: $0.height,
                                       name: $0.name)
                    }
                }
            }
            noteQuestionSettled(callId: callId)
        case .turnStart(let sequence, let turn):
            if !turnStarts.contains(sequence) { turnStarts.append(sequence) }
            isTurnRunning = true
            if turnStartedAt == nil { turnStartedAt = Date() }
            if let pendingTurn = activeConversation?.pendingQuestionTurn, turn > pendingTurn {
                clearPendingQuestion()
            }
            Task { await activeConversation?.coordinator?.setExpectingActivity(true) }
        case .turnEnd(let sequence, let turn, let failure):
            // 这一轮结束了：同轮里还没收到结果的步骤（例如被中断的提问）不能再显示进行时。
            markUnfinishedStepsEnded(turn: turn)
            recordTurnFailure(sequence: sequence, failure: failure)
            activeConversation?.endedTurnNumbers.insert(turn)
            if activeConversation?.pendingQuestionTurn == turn {
                clearPendingQuestion()
            }
            Task { await activeConversation?.coordinator?.setExpectingActivity(false) }
        }
    }

    /// 记录一轮结束。失败时把原因留在时间线里，而不是只把「正在运行」关掉。
    @MainActor
    func recordTurnFailure(sequence: Int, failure: DSHTurnFailure?) {
        if !turnEnds.contains(sequence) { turnEnds.append(sequence) }
        isTurnRunning = false
        turnStartedAt = nil
        guard let failure else { return }
        guard !turnFailures.contains(where: { $0.sequence == sequence }) else { return }
        turnFailures.append(TurnFailureNotice(sequence: sequence, message: failure.message, code: failure.code))
        turnFailures.sort { $0.sequence < $1.sequence }
    }

    /// 只有「还没结果，且这一轮还没结束」才占输入区。历史重放不能把答过的问题再抬出来。
    /// 解析交由 DSHKit（纯逻辑、可单测），这里只做类型转换。
    static func parsePendingQuestion(callId: String, arguments: String) -> PendingUserQuestion? {
        guard let payload = PendingQuestionPayload.decode(callId: callId, arguments: arguments) else {
            return nil
        }
        return PendingUserQuestion(payload: payload)
    }

    /// 回答 `ask_user_question`（userQuestions/answer）。
    @MainActor
     static func pocketMessage(from message: DSHMessage) -> PocketMessage {
        PocketMessage(sequence: message.sequence,
                      kind: message.kind,
                      text: message.text,
                      isUser: message.isUser,
                      rpcId: message.rpcId,
                      images: message.images.map {
                          PocketImageRef(attachmentId: $0.attachmentId,
                                         mediaType: $0.mediaType,
                                         bytes: $0.bytes ?? 0,
                                         width: $0.width,
                                         height: $0.height,
                                         name: $0.name)
                      })
    }

    static func appConnectionState(from state: SyncConnectionState) -> LiveConnectionState {
        switch state {
        case .idle: return .idle
        case .connecting: return .connecting
        case .connected: return .connected
        case .reconnecting(let attempt): return .reconnecting(attempt: attempt)
        case .disconnected(let reason): return .disconnected(reason: reason)
        }
    }

    /// 手动重连实时流（状态机断开时 UI 上的"重连"按钮）。
    // MARK: 问答卡（实现在 QuestionInbox）

    @MainActor
    func noteQuestionAsked(callId: String, turn: Int, arguments: String) {
        questionInbox.noteAsked(callId: callId, turn: turn, arguments: arguments)
    }

    @MainActor
    func noteQuestionSettled(callId: String) {
        questionInbox.noteSettled(callId: callId)
    }

    @MainActor
    func clearPendingQuestion() {
        questionInbox.clear()
    }

    @MainActor
    func answerQuestion(_ request: PendingUserQuestion,
                        selected: [String: Set<String>],
                        custom: [String: String]) {
        questionInbox.answer(request, selected: selected, custom: custom)
    }

    /// 装配问答卡的依赖（幂等，RootView onAppear 调用）。
    func installQuestionProviders() {
        guard questionInbox.providers == nil else { return }
        questionInbox.providers = QuestionInbox.Providers(
            sessionId: { [weak self] in self?.selectedSession?.sessionId },
            conversation: { [weak self] in self?.activeConversation },
            client: { [weak self] in
                guard let self else { throw ConnectionError.invalidURL("") }
                return try self.rpcClient
            },
            record: { @MainActor [weak self] message in self?.recordDiagnostic(message) },
            reportError: { @MainActor [weak self] message in self?.conversationError = message }
        )
    }

    @MainActor
    func manualReconnect() {
        guard let session = selectedSession, !isDemoMode else { return }
        liveConnection = .connecting
        recordDiagnostic("手动重连实时流")
        if let coordinator = activeConversation?.coordinator {
            Task { await coordinator.reconnect() }
            return
        }
        liveTask?.cancel()
        fallbackTask?.cancel()
        liveTask = Task { await loadConversation(session) }
    }

    /// 停止当前这一轮生成（消息已发出、正在等回复时使用）。
    @MainActor
    func cancelTurn() async {
        guard let session = selectedSession, !isDemoMode else { return }
        do {
            _ = try await rpcClient.rpcAdapted("session/cancel", args: ["request": ["sessionId": session.sessionId]])
            isTurnRunning = false
            recordDiagnostic("已请求停止当前生成")
        } catch {
            conversationError = "停止失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    func performSend(text: String, attachments: [PocketDraftImage]) async {
        guard let session = selectedSession, !isSending else { return }
        let sendConversation = conversations[session.sessionId]
        let lastSequence = messages.filter { !$0.isPending }.map(\.sequence).max() ?? -1
        let requestId = UUID().uuidString.lowercased()
        let sortAnchor = TimelineOrdering.pendingAnchor(
            messageMax: lastSequence,
            stepMax: steps.map(\.sequence).max() ?? -1
        )
        let pending = PocketMessage(pendingText: text, localImages: attachments.map(\.uiImage), rpcId: requestId, sortSequence: sortAnchor)
        let sendStarted = Date()
        timingLog("send_typed chars=\(text.count) images=\(attachments.count)")
        recordDiagnostic("用户点击发送：\(text.count) 字，图片 \(attachments.count) 张")
        messages.append(pending)
        pendingSendID = pending.id
        pendingSendRpcId = requestId
        addOutbox(sessionId: session.sessionId, rpcId: requestId, text: text, images: attachments)
        cancelledDraft = text
        cancelledImages = attachments
        draft = ""
        draftImages = []
        if let sendConversation {
            sendConversation.draft = ""
            sendConversation.draftImages = []
        }
        DraftStore.save("", for: session.sessionId)
        DraftImageStore.clear(sessionId: session.sessionId)
        isSending = true
        defer {
            isSending = false
            pendingSendID = nil
            pendingSendRpcId = nil
            cancelledDraft = ""
            cancelledImages = []
        }
        do {
            timingLog("prompt_start chars=\(text.count) images=\(attachments.count)")
            // 请求体结构在 DSHKit（可测）：空文本不产生 text block、图片字段名固定。
            let payloadImages = attachments.map {
                PromptPayload.Image(mediaType: $0.mediaType,
                                    base64: $0.data.base64EncodedString(),
                                    name: $0.name)
            }
            // 只有「确认过实时 turn 事件、且确实在跑」才用 steer 打断；
            // 没见到实时事件时按 queue 处理——queue 最多排到本轮之后，steer 会打断正在做的事。
            let promptMode = PromptPolicy.liveMode(isRunning: isTurnRunning).rawValue
            recordDiagnostic("发送模式：\(promptMode)（生成中=\(isTurnRunning)）")
            _ = try await rpcClient.rpcWithRetryAdapted("session/prompt", args: ["request": [
                "requestId": requestId,
                "sessionId": session.sessionId,
                "mode": promptMode,
                "content": PromptPayload.content(text: text, images: payloadImages),
                "clientTimeZone": TimeZone.current.identifier
            ]])
            timingLog("prompt_ack elapsed_ms=\(Int(Date().timeIntervalSince(sendStarted) * 1000))")
            recordDiagnostic("服务端已确认发送，耗时 \(Int(Date().timeIntervalSince(sendStarted) * 1000)) 毫秒")
            ackedSendRpcIds.insert(requestId)
            markOutboxAccepted(rpcId: requestId)
            if promptMode == "steer" { activeConversation?.steeredRpcIds.insert(requestId) }
            Task { await activeConversation?.coordinator?.setExpectingActivity(true) }
            conversationError = nil
            // 服务端已受理：立刻结束"发送中"状态，恢复发送按钮；若为 steer，服务端会打断当前轮。
            isSending = false
            pendingSendID = nil
            cancelledDraft = ""
            cancelledImages = []
            // 先用服务端真实用户消息替换本地待确认消息，保证"用户消息在上、助手回复在下"的顺序；
            // 否则实时回复先到、轮询提前退出时，待确认消息会带着临时序号排在回复后面。
            await loadHistory(session)
            await pollForReply(session, after: text, afterSequence: lastSequence)
            // 服务端 ACK 后如果还没收到确认，先主动核验一次（网络抖动时 WS/轮询可能错过确认），
            // 核验不到再标记失败，避免误报吓人。
            if ackedSendRpcIds.contains(requestId) && promptMode == "steer" {
                // steer 进入 agent inbox，后续会被注入成 user/message；
                // 此阶段核验不到是正常现象，绝不能标失败（显示"已送达，排队等待处理"）。
                if case .landed = await verifySendLanded(session: session, requestId: requestId) {
                    confirmOutbox(rpcIds: [requestId])
                    ackedSendRpcIds.remove(requestId)
                    failedSendRpcIds.remove(requestId)
                    conversationError = nil
                    recordDiagnostic("steer 已落库确认：\(requestId)")
                } else {
                    conversationError = nil
                    recordDiagnostic("steer 已 ACK，等待注入为 user/message：\(requestId)")
                }
            } else if ackedSendRpcIds.contains(requestId) {
                switch await verifySendLanded(session: session, requestId: requestId) {
                case .landed:
                    confirmOutbox(rpcIds: [requestId])
                    ackedSendRpcIds.remove(requestId)
                    failedSendRpcIds.remove(requestId)
                    conversationError = nil
                    recordDiagnostic("发送核验成功：\(requestId)")
                case .absent:
                    failedSendRpcIds.insert(requestId)
                    ackedSendRpcIds.remove(requestId)
                    markOutboxSendFailed(rpcId: requestId)
                    conversationError = "这条消息服务端没有收到，点消息下方「重新发送」可重试（按 requestId 去重，不会重复）。"
                    recordDiagnostic("发送核验失败（服务端无此消息）：\(requestId)")
                case .unreachable:
                    // 网络抖动导致核验请求本身失败：不能误报失败，保持"已发出，等待处理"，后台再核验。
                    recordDiagnostic("发送核验网络不可达，稍后重试：\(requestId)")
                    scheduleSendReverification(session: session, requestId: requestId, attempt: 1)
                }
            }
        } catch {
            // 处置优先级在 DSHKit（可测）：取消 > 登录失效 > 网络不通 > 其它失败。
            let isCancelled = Task.isCancelled || (error as? URLError)?.code == .cancelled
            let unauthorized: Bool = {
                if (error as? ConnectionError)?.isUnauthorized == true { return true }
                return false
            }()
            let action = SendFailurePolicy.action(isCancelled: isCancelled,
                                                  isUnauthorized: unauthorized,
                                                  isTransient: isTransientNetworkError(error),
                                                  isStaleTunnel: isStaleTunnelError(error))
            switch action {
            case .returnToComposer:
                // 用户取消：正文退回输入框，再删本机副本；否则留着等重发。
                if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draft = pending.text
                }
                if OutboxRetentionPolicy.canRemove(cause: .userCancelled) {
                    removeOutbox(rpcIds: [requestId])
                    messages.removeAll { $0.id == pending.id }
                } else {
                    failedSendRpcIds.insert(requestId)
                    markOutboxSendFailed(rpcId: requestId)
                }
            case .reauthenticate:
                // 登录失效不等于这条消息该丢：正文留在发件箱并标失败，重新登录后可重发。
                if OutboxRetentionPolicy.canRemove(cause: .authExpired) {
                    removeOutbox(rpcIds: [requestId])
                    messages.removeAll { $0.id == pending.id }
                } else {
                    failedSendRpcIds.insert(requestId)
                    markOutboxSendFailed(rpcId: requestId)
                    recordDiagnostic("登录失效，正文保留在发件箱：\(requestId)")
                }
                handleAuthExpired()
            case .holdOffline:
                queuedSendRpcIds.insert(requestId)
                failedSendRpcIds.remove(requestId)
                markOutboxHeldOffline(rpcId: requestId)
                conversationError = nil
                recordDiagnostic("网络不可达，已写入断网暂存，联网后一并发送：\(requestId)")
            case .markFailed:
                // 其它错误：正文留在发件箱，标记失败，用户可直接重发。
                failedSendRpcIds.insert(requestId)
                markOutboxSendFailed(rpcId: requestId)
                conversationError = "发送失败：\(error.localizedDescription)（点消息气泡下方「重新发送」可重试）"
            }
        }
    }

    /// 对网络抖动做有限重试（仅用于幂等请求：session/prompt 按 requestId 去重、session/page 只读）。
     func isTransientNetworkError(_ error: Error) -> Bool {
        DSHNetworkErrorPolicy.isTransient(error)
    }

    /// 主动核验消息是否真的落库：在最近会话历史里按 rpcId 精确查找。
    func verifySendLanded(session: PocketSession, requestId: String) async -> SendVerification {
        var sawReachableResponse = false
        for attempt in 0..<4 {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(attempt == 1 ? 1 : attempt == 2 ? 2 : 4))
            }
            guard let value = try? await rpcClient.rpcAdapted("session/page", args: ["request": [
                "address": ["kind": "session", "sessionId": session.sessionId],
                "maxMessages": 30
            ]]) else { continue }
            sawReachableResponse = true
            let records = value["records"] as? [[String: Any]] ?? []
            // 扫描规则在 DSHKit（可测）：user/message 或 agent/inbox/spliced 都算已送达。
            if SendLandedScan.landed(inRecords: records, requestId: requestId) { return .landed }
        }
        return sawReachableResponse ? .absent : .unreachable
    }

    /// RPC 唯一入口。协议实现（envelope / 超时 / 状态码）在 DSHKit，这里只做错误适配。
    ///
    /// 分界线：传输层错误（`URLError`）原样向上抛，交给 `isTransientNetworkError` 判断可否重试；
    /// 协议错误（`DSHError`）适配成 `ConnectionError`，保持 UI 文案与分类不变。
 }

// MARK: 通知域（实现在 NotificationBridge）

extension ConnectionModel {
    @MainActor func syncPushRegistration() async { await notificationBridge.syncPushRegistration() }

    @MainActor
    func sendNotificationReply(sessionId: String, text: String) async {
        await notificationBridge.sendReply(sessionId: sessionId, text: text)
    }

    @MainActor
    func openSessionFromNotification(sessionId: String) async {
        await notificationBridge.openSessionFromNotification(sessionId: sessionId)
    }

    /// 装配通知域依赖（幂等）。
    @MainActor
    func installNotificationProviders() {
        guard notificationBridge.providers == nil else { return }
        notificationBridge.providers = NotificationBridge.Providers(
            client: { [weak self] in
                guard let self else { throw ConnectionError.invalidURL("") }
                return try self.rpcClient
            },
            isConnected: { [weak self] in self?.isConnected ?? false },
            pin: { [weak self] in self?.pin ?? "" },
            setPin: { @MainActor [weak self] value in self?.pin = value },
            savedPin: { PinKeychain.load() },
            savedAddress: { UserDefaults.standard.string(forKey: ConnectionModel.savedServerAddressKey) },
            serverAddress: { [weak self] in self?.serverAddress ?? "" },
            setServerAddress: { @MainActor [weak self] value in self?.serverAddress = value },
            connect: { @MainActor [weak self] in await self?.connect() },
            sessions: { [weak self] in self?.sessions ?? [] },
            openSession: { @MainActor [weak self] sessionId in
                guard let self, let session = self.sessions.first(where: { $0.sessionId == sessionId }) else { return }
                self.navigationPath = [session]
            },
            insertAckedRpcId: { @MainActor [weak self] rpcId in self?.ackedSendRpcIds.insert(rpcId) },
            addOutbox: { @MainActor [weak self] sessionId, rpcId, text in
                self?.addOutbox(sessionId: sessionId, rpcId: rpcId, text: text)
            },
            clearFinishedAwaiting: { @MainActor [weak self] sessionId in
                guard let self else { return }
                if self.finishedAwaitingSessionIds.remove(sessionId) != nil {
                    self.persistFinishedAwaiting()
                }
            },
            completionAlertsEnabled: { [weak self] in self?.completionAlertsEnabled ?? false },
            pushToken: { [weak self] in self?.pushToken },
            record: { @MainActor [weak self] message in self?.recordDiagnostic(message) }
        )
    }
}
