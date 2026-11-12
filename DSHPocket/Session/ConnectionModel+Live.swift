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
              let base = try? Self.serverURL(from: connection.serverAddress) else { return false }
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
        connection.isConnected = false
        connection.pin = ""
        PinKeychain.clear()
        // cookie 已失效：清掉，避免下次启动拿着废凭证反复 401。
        // 地址保留，用户重新输入密码/扫码即可，不必重新找电脑。
        ConnectionVault.clearAuthCookies()
        if let base = try? Self.serverURL(from: connection.serverAddress) { purgeAuthCookies(for: base) }
        sessionStore.selected = nil
        sessionStore.navigationPath = []
        activeConversation?.liveTask?.cancel()
        liveConnection = .disconnected(reason: "auth")
        connection.errorMessage = L10n.t("登录已过期（DSH 可能重启过），请重新扫码配对或输入访问密码。")
    }

    /// 发送按钮入口：先确认当前打开的就是这个会话，避免消息发到别的 session。
    @MainActor
     /// 同步清空当前输入框 + 该会话的持久化草稿；下一轮 runloop 再清一次，兜住输入法回填。
     /// 取消"发送中"的消息：撤回本地待确认气泡，恢复输入内容。
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
            sessionId: { [weak self] in self?.sessionStore.selected?.sessionId },
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
        guard let session = sessionStore.selected, !isDemoMode else { return }
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
        guard let session = sessionStore.selected, !isDemoMode else { return }
        do {
            _ = try await rpcClient.rpcAdapted("session/cancel", args: ["request": ["sessionId": session.sessionId]])
            isTurnRunning = false
            recordDiagnostic("已请求停止当前生成")
        } catch {
            conversationError = "停止失败：\(error.localizedDescription)"
        }
    }

     /// 对网络抖动做有限重试（仅用于幂等请求：session/prompt 按 requestId 去重、session/page 只读）。
     func isTransientNetworkError(_ error: Error) -> Bool {
        DSHNetworkErrorPolicy.isTransient(error)
    }

    /// 主动核验消息是否真的落库：在最近会话历史里按 rpcId 精确查找。
     /// RPC 唯一入口。协议实现（envelope / 超时 / 状态码）在 DSHKit，这里只做错误适配。
    ///
    /// 分界线：传输层错误（`URLError`）原样向上抛，交给 `isTransientNetworkError` 判断可否重试；
    /// 协议错误（`DSHError`）适配成 `ConnectionError`，保持 UI 文案与分类不变。
 }
