// 发送、实时帧和 RPC

import SwiftUI
import Security
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
        if !authRefreshAttempted, ConnectionVault.loadDeviceToken(for: connection.serverAddress) != nil {
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
        await tryRefreshAuth(for: connection.serverAddress)
    }

    /// 用指定地址的设备凭证换新票（不依赖当前连接）。
    ///
    /// 为什么需要参数：切换连接时目标是「另一台机器」，它的 cookie 早就过期了，
    /// 而旧的 `tryRefreshAuth()` 只会刷新 `connection.serverAddress`——那正是我们
    /// 还没切过去的那台。结果就是「探针 401 → 判定目标不可用」，永远换不过去。
    @MainActor
    func tryRefreshAuth(for address: String) async -> Bool {
        // 串行化：并发换票会让彼此的 cookie 互相作废（服务端一直 ok、客户端一直 401）。
        if let inFlight = refreshTasksByAddress[address] {
            return await inFlight.value
        }
        let task = Task { @MainActor in await self.performRefresh(for: address) }
        refreshTasksByAddress[address] = task
        let result = await task.value
        refreshTasksByAddress[address] = nil
        return result
    }

    @MainActor
    private func performRefresh(for address: String) async -> Bool {
        guard let token = ConnectionVault.loadDeviceToken(for: address),
              let base = try? Self.serverURL(from: address) else { return false }
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
        // 换票响应顺带带回机器名：客户端靠它把「同一台机器的多条地址」归成一组。
        // 这条通道本来就要走（换票），所以不额外增加请求。
        if let machine = http.value(forHTTPHeaderField: "x-dsh-machine"), !machine.isEmpty {
            learnMachine(machine, for: address)
        }
        // 必须是新换到的 cookie：请求前已清空旧 cookie，这里能查到就是新的。
        let fresh = HTTPCookieStorage.shared.cookies(for: base)?
            .contains { $0.name.hasPrefix("dsh-auth") } ?? false
        if fresh {
            // 换票成功说明登录态已恢复：复位「换过一次票」标记，
            // 否则之后再遇 401 会直接登出，用户只能重扫（2026-11-26 复现）。
            authRefreshAttempted = false
            ConnectionVault.saveAuthCookies(from: base, address: address)
            return true
        }
        // 没拿到 cookie：把插件返回的 ok:false 说明记下来，便于排查。
        let snippet = String(data: data.prefix(120), encoding: .utf8) ?? ""
        recordDiagnostic("设备凭证换票失败：未拿到新 cookie（\(snippet)）")
        return false
    }

    /// 记住某个地址属于哪台机器，并在必要时**合并主机**。
    ///
    /// 主机模型下 machine 的用途变了：不再是「分组用的标签」，
    /// 而是「这两台主机其实是同一台机器」的判据——
    /// 比如先扫了局域网地址、后扫了 Tailscale 地址，两者 hostname 相同就该并成一台。
    @MainActor
    func learnMachine(_ machine: String, for address: String) {
        if let url = try? Self.serverURL(from: address),
           let current = try? Self.serverURL(from: connection.serverAddress),
           DSHURL.baseAddress(url) == DSHURL.baseAddress(current) {
            currentMachineName = machine
        }
        guard let index = hosts.firstIndex(where: { $0.endpoints.contains { $0.address == address } }) else { return }
        if hosts[index].machine != machine {
            hosts[index].machine = machine
            persistHosts()
            recordDiagnostic("学到机器名：\(machine) → \(DSHURL.redactedAddress(address))")
        }
        mergeHosts(sharingMachine: machine)
    }

    /// 把 machine 相同的多台主机并成一台：保留最近用的那台的名字，地址合并去重。
    @MainActor
    func mergeHosts(sharingMachine machine: String) {
        let group = hosts.filter { $0.machine == machine }
        guard group.count > 1 else { return }
        guard var keep = group.max(by: { $0.lastUsedAt < $1.lastUsedAt }) else { return }
        var seen = Set<String>()
        keep.endpoints = group.flatMap(\.endpoints).filter { seen.insert($0.address).inserted }
        keep.lastUsedAt = group.map(\.lastUsedAt).max() ?? keep.lastUsedAt
        let removed = Set(group.map(\.id)).subtracting([keep.id])
        if let cid = currentHostId, removed.contains(cid) { currentHostId = keep.id }
        hosts = hosts.filter { !removed.contains($0.id) }
        if let i = hosts.firstIndex(where: { $0.id == keep.id }) { hosts[i] = keep }
        persistHosts()
        recordDiagnostic("合并主机：\(machine)，现有 \(hosts.count) 台")
    }

    /// 给还没有机器名的旧地址补一次名字。
    ///
    /// 为什么需要：分组依赖机器名，而机器名是这次改动才引入的，用户已有的地址全是空的——
    /// 那样它们会各自成一组，看起来比改动前还乱。这里在打开设置时静默补一次。
    @MainActor
    func backfillMachineNames() async {
        // 逐个「还不知道机器名」的主机，问它首选地址一次（响应头带 x-dsh-machine）。
        //
        // 之前这里遍历的是 savedEndpoints（旧扁平列表），而分组用的是 hosts；
        // 结果列表里有机器名的主机一个也没被补上 → 同一台机器永远合不到一起
        // （2026-11-25 实测：真机存档里 3 台主机的 machine 全是 nil）。
        let pending = hosts.filter { ($0.machine ?? "").isEmpty }
        guard !pending.isEmpty else { return }
        for host in pending {
            guard let endpoint = host.preferredEndpoint,
                  let base = try? Self.serverURL(from: endpoint.address) else { continue }
            // 先试换票（顺带把 cookie 刷新），失败也要继续——有些地址 cookie 还有效。
            _ = await tryRefreshAuth(for: endpoint.address)
            if let machine = await fetchMachineName(at: base) {
                learnMachine(machine, for: endpoint.address)
            }
        }
    }

    /// 直接问一次插件拿机器名（读响应头，不解析 body）。
    @MainActor
    func fetchMachineName(at base: URL) async -> String? {
        var request = URLRequest(url: base.appending(path: "dsh-pocket-ios/tailscale.status"))
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = true
        let envelope: [String: Any] = [
            "type": "client-request",
            "rpcId": UUID().uuidString,
            "method": "tailscale.status",
            "payload": ["args": [:] as [String: Any]],
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: envelope) else { return nil }
        request.httpBody = body
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              let name = http.value(forHTTPHeaderField: "x-dsh-machine"),
              !name.isEmpty else { return nil }
        return name
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
        ConnectionVault.clearAuthCookies(for: connection.serverAddress)
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
        // hasMoreOlder 恒为 false（产品只保留最近 30 条），这里保留 guard 作为双保险。
        guard !isDemoMode, !isLoadingOlder, hasMoreOlder,
              let coordinator = activeConversation?.coordinator,
              let oldest = messages.min(by: { $0.sequence < $1.sequence }) else { return }
        isLoadingOlder = true
        olderAnchorID = oldest.id
        if let conversation = activeConversation {
            conversation.olderLoadAttempts += 1
            conversation.olderLoadLastAt = Date()
            conversation.olderLoadLastResult = "requesting"
        }
        recordDiagnostic("请求更早历史：beforeSeq=\(oldest.sequence) hasMore=\(hasMoreOlder) total=\(messages.count)")
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
            // 快照也是一次「收到数据」，要计入实时帧信号。
            // 否则打开会话后 Live Signal 显示 0 帧 / 83 秒，看起来像实时流断了
            // （真机实测踩过：这个会话明明刚加载过快照）。
            recordLiveFrameArrival()
            // 先结算「已回答」再重放步骤：否则 tool/call 会把答过的问题重新抬成卡片
            // （2026-11-24 真机反馈：回答完退出再进，卡片又弹出来）。
            mergeMessages(settleQuestionReplies(in: dshMessages).map(Self.pocketMessage(from:)))
            for step in dshSteps { applyDSHStep(step, historical: true) }
            // 快照到达时总是允许上滑试一次。
            //
            // 三个坑叠在一起，导致这个开关一直是 false、上滑永远不触发（2026-11-22）：
            //   1. 这里曾写死 false（旧决策「不做上滑历史」）；
            //   2. 服务端 hasMore 实测不可靠（10357 条的会话回 false）；
            //   3. 「不满页就判定到底」也不成立（请求 24 条只回 13 条）。
            // 结论：不要用任何服务端字段决定「能不能翻」，改成
            // 「这一页有没有真的取到更早的消息」——没有才算到底（见 loadOlder）。
            _ = hasMore
            hasMoreOlder = true
            isLoadingConversation = false
            activeConversation?.trimMessages(to: Self.inSessionMessageLimit)
            noteLoadFinished(source: "snapshot", conversation: conversation)
        case .messages(let dshMessages):
            let beforeCount = messages.count
            mergeMessages(settleQuestionReplies(in: dshMessages).map(Self.pocketMessage(from:)))
            isLoadingConversation = false
            if isLoadingOlder {
                isLoadingOlder = false
                olderLoadTick += 1
                if let conversation = activeConversation {
                    conversation.olderLoadSuccesses += 1
                    conversation.olderLoadLastAdded = max(0, messages.count - beforeCount)
                    conversation.olderLoadLastAt = Date()
                    conversation.olderLoadLastResult = "ok +\(conversation.olderLoadLastAdded)"
                }
            }
            // 只保留最近 N 条（保最新、裁最旧）。
            // 不再区分方向：已经关闭分页，不存在「上滑加载更早的」这条路径了。
            if let conversation = activeConversation {
                conversation.trimMessages(to: Self.inSessionMessageLimit)
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
            // `{"pending":true}` 表示超时后问题仍可回答：此时不能结算，否则卡片被永久吞掉。
            if !QuestionAnswerReplay.isPendingResult(text) {
                noteQuestionSettled(callId: callId)
            }
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

    @MainActor
     static func pocketMessage(from message: DSHMessage) -> PocketMessage {
        return PocketMessage(sequence: message.sequence,
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
                      },
                      turn: message.turn)
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

    /// 问答卡的回复不是对话消息（正文是一段 JSON 答案）：用它结算卡片，并从渲染列表里剔除。
    ///
    /// 这是「已回答」在日志里的持久证据——App 重启、电脑端已回答、步骤窗口截断都靠它兜住。
    /// 判定依据与 DSH 的 `userQuestions` 投影一致（`source.kind == "user-question-reply"`）。
    @MainActor
    func settleQuestionReplies(in dshMessages: [DSHMessage]) -> [DSHMessage] {
        dshMessages.filter { message in
            guard message.sourceKind == "user-question-reply" else { return true }
            if let callId = message.sourceCallId, !callId.isEmpty {
                noteQuestionSettled(callId: callId)
            }
            return false
        }
    }

    /// 问答卡的回复不是对话消息（正文是 JSON 答案）：用它结算卡片。
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
    @MainActor
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
            reportError: { @MainActor [weak self] message in self?.conversationError = message },
            sendRemoteResult: { @MainActor [weak self] clientId, eventId, value in
                await self?.sendRemoteEventResult(clientId: clientId, eventId: eventId, value: value)
            }
        )
        // 顺带启动 `$events` 通道（幂等）：手机端要能直接回答问答卡，就必须走这条通道。
        startRemoteEvents()
    }

    /// 启动 `$events` 通道（幂等）。
    @MainActor
    func startRemoteEvents() {
        guard remoteEventsTask == nil else { return }
        remoteEventsTask = Task { [weak self] in
            guard let self else { return }
            await self.runRemoteEvents()
        }
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
