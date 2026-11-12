// 会话列表、历史和实时流

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

    /// 用最新 session 列表更新 running 状态机，识别"运行中 → 已结束"的会话。
    @MainActor
    func detectSessionCompletions() {
        let latest = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionId, $0.running) })
        let completed = completionTracker.update(latest: latest)
        UserDefaults.standard.set(latest, forKey: Self.runningSnapshotKey)
        recordDiagnostic("可用会话刷新：\(latest.count) 个，完成事件 \(completed.count) 个")

        // 重新开始运行的会话不再算"等待回复"。
        for session in sessions where session.running {
            finishedAwaitingSessionIds.remove(session.sessionId)
        }

        guard !completed.isEmpty else { return }
        for sessionId in completed {
            guard let session = sessions.first(where: { $0.sessionId == sessionId }) else { continue }
            let viewing = visibleSessionId == sessionId && isAppActive
            if viewing {
                finishedAwaitingSessionIds.remove(sessionId)
            } else {
                finishedAwaitingSessionIds.insert(sessionId)
                if completionAlertsEnabled { playCompletionFeedback(for: session) }
            }
        }
        persistFinishedAwaiting()
    }

    @MainActor
    func markFinishedAwaitingRead(_ sessionId: String) {
        if finishedAwaitingSessionIds.remove(sessionId) != nil {
            persistFinishedAwaiting()
        }
    }

    @MainActor
    func toggleCompletionAlerts() {
        completionAlertsEnabled.toggle()
        UserDefaults.standard.set(completionAlertsEnabled, forKey: Self.completionAlertKey)
        if completionAlertsEnabled,
           ProcessInfo.processInfo.environment["DSH_NO_NOTIF_PROMPT"] != "1" {
            CompletionNotifier.shared.requestPermission()
            Task { await syncPushRegistration() }
        } else if let token = pushToken {
            Task { _ = try? await rpcClient.rpcAdapted("push.unregister", args: ["token": token]) }
        }
        recordDiagnostic("完成提醒：\(completionAlertsEnabled ? "开启" : "关闭")")
    }

    @MainActor
    func playCompletionFeedback(for session: PocketSession) {
        CompletionNotifier.shared.notify(sessionId: session.sessionId, title: session.displayTitle)
        // 通知被关闭时也有声音兜底。
        AudioServicesPlaySystemSound(1007)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        recordDiagnostic("完成提醒：\(session.displayTitle)")
    }

    @MainActor
    func persistFinishedAwaiting() {
        UserDefaults.standard.set(Array(finishedAwaitingSessionIds), forKey: Self.finishedAwaitingKey)
    }

    @MainActor
    func loadSessions(silently: Bool = false) async {
        if isDemoMode { return }
        guard !isLoadingSessions else { return }
        if !silently { isLoadingSessions = true }
        defer { isLoadingSessions = false }
        do {
            sessions = try await fetchSessions()
            syncSelectedSessionMetadata()
            detectSessionCompletions()
            errorMessage = nil
            recordDiagnostic("会话列表刷新：\(sessions.count) 个，隐藏归档 \(archivedSessionIds.count) 个")
            // 能拉到列表说明网络通了：把各会话的断网暂存按写入顺序一并补发。
            flushQueuedSends()
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            if let authError = error as? ConnectionError,
               case .server(let status) = authError,
               TimelineOrdering.isUnauthorized(statusCode: status) {
                recordDiagnostic("会话列表 401：登录已失效")
                handleAuthExpired()
                return
            }
            recordDiagnostic("会话列表刷新失败：\(error.localizedDescription)")
            if isStaleTunnelError(error) {
                applyConnectError(error)
                return
            }
            // 后台轮询、下拉刷新之外的自动刷新失败不该顶一条红字：网络抖一下就挂在那里，
            // 用户没做任何操作却被吓一跳。只有列表本来就是空的、或用户主动刷新时才提示。
            let transient = Self.isTransientNetworkError(error)
            if transient, silently || !sessions.isEmpty {
                recordDiagnostic("会话列表刷新遇到网络抖动，保留当前列表")
                return
            }
            errorMessage = transient
                ? "连接电脑超时，正在重试…"
                : "无法读取会话：\(error.localizedDescription)"
            scheduleSessionListRetry()
        }
    }

    /// 超时/断连这类抖动：自动退避重试，成功就把红字清掉。
    @MainActor
    func scheduleSessionListRetry() {
        sessionListRetryTask?.cancel()
        sessionListRetryTask = Task { [weak self] in
            for delay in [2.0, 4.0, 8.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled else { return }
                await self.loadSessions(silently: true)
                if await MainActor.run(body: { self.errorMessage == nil }) { return }
            }
        }
    }

    static func isTransientNetworkError(_ error: Error) -> Bool {
        DSHNetworkErrorPolicy.isTransient(error)
    }

    func fetchSessions() async throws -> [PocketSession] {
        // 列表只拉一份摘要，20 秒还没回来基本就是连不上，早点交给重试。
        let value = try await rpcClient.rpcAdapted("session/list", args: ["_request": ["excludeArchived": true]], timeout: 20)
        let items = value["items"] as? [[String: Any]] ?? []
        let sessions = items.compactMap(PocketSession.init(json:))
        let archived: Set<String>
        if value["archivedSessionsExcluded"] as? Bool == true {
            archived = []
            pinnedSessionIds = []
        } else {
            let flags = try await fetchWorkspaceSessionFlags()
            archived = flags.archived
            pinnedSessionIds = flags.pinned
        }
        archivedSessionIds = archived
        // 与 DSH 桌面端侧边栏保持一致：隐藏已归档、subagent 子会话和空会话，
        // 这样 iOS 列表数量和 Mac 端看到的数量一致。
        return sessions.filter { !archived.contains($0.sessionId) && !$0.isSubagent && !$0.isHiddenFromList }
    }

    func fetchWorkspaceSessionFlags() async throws -> (archived: Set<String>, pinned: [String]) {
        guard let base = try? Self.serverURL(from: serverAddress),
              let socketURL = Self.webSocketURL(from: base, path: "api/remote.mux") else {
            throw ConnectionError.invalidURL(serverAddress)
        }
        let socket = URLSession.shared.webSocketTask(with: socketURL)
        let streamId = UUID().uuidString
        let open = StreamOpen(type: "open", streamId: streamId, endpoint: "workspace/follow", payload: ["args": [:]])
        let timeout = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { socket.cancel(with: .goingAway, reason: nil) }
        }
        defer {
            timeout.cancel()
            socket.cancel(with: .goingAway, reason: nil)
        }
        socket.resume()
        let encoded = try JSONEncoder().encode(open)
        guard let requestText = String(data: encoded, encoding: .utf8) else { throw ConnectionError.invalidPayload }
        try await socket.send(.string(requestText))
        while true {
            let frame = try await socket.receive()
            let data: Data
            switch frame {
            case .data(let bytes): data = bytes
            case .string(let text): data = Data(text.utf8)
            @unknown default: continue
            }
            guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  envelope["streamId"] as? String == streamId,
                  envelope["type"] as? String == "item",
                  let value = envelope["value"] as? [String: Any] else { continue }
            guard value["type"] as? String == "baseline",
                  let baseline = value["value"] as? [String: Any],
                  let archived = baseline["archivedSessionIds"] as? [String] else {
                throw ConnectionError.invalidPayload
            }
            let pinned = baseline["pinnedSessionIds"] as? [String] ?? []
            return (Set(archived), pinned)
        }
    }

    /// 重命名会话（DSH `session/rename`，桌面端同步）。
    @MainActor
    func rename(_ session: PocketSession, to rawTitle: String) async {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if !isDemoMode {
            do {
                _ = try await rpcClient.rpcAdapted("session/rename", args: ["request": [
                    "sessionId": session.sessionId,
                    "title": title
                ]])
            } catch {
                errorMessage = "重命名失败：\(error.localizedDescription)"
                return
            }
        }
        let updated = PocketSession(
            sessionId: session.sessionId, updatedAt: session.updatedAt,
            running: session.running, blank: session.blank,
            title: title, cwd: session.cwd,
            origin: session.origin, parentSessionId: session.parentSessionId
        )
        if let index = sessions.firstIndex(where: { $0.sessionId == session.sessionId }) {
            sessions[index] = updated
        }
        if selectedSession?.sessionId == session.sessionId { selectedSession = updated }
    }

    @MainActor
    func loadModelCatalog() async {
        guard !isDemoMode else { return }
        do {
            let value = try await rpcClient.rpcAdapted("session/modelCatalog", args: [:])
            let groups = value["groups"] as? [[String: Any]] ?? []
            modelGroups = groups.compactMap { group in
                guard let id = group["id"] as? String,
                      let name = group["name"] as? String else { return nil }
                let models = (group["models"] as? [[String: Any]] ?? []).compactMap { item -> ModelOption? in
                    guard let model = item["id"] as? String else { return nil }
                    return ModelOption(provider: id, model: model,
                                       name: item["name"] as? String ?? model)
                }
                return ModelGroup(id: id, name: name, models: models)
            }
            if selectedModelLabel == nil,
               let defaultSel = value["default"] as? [String: Any],
               let provider = defaultSel["provider"] as? String,
               let model = defaultSel["model"] as? String {
                selectedModelLabel = modelGroups.first { $0.id == provider }?
                    .models.first { $0.model == model }?.name ?? model
            }
        } catch {
            recordDiagnostic("模型列表加载失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    func selectModel(_ option: ModelOption) async {
        guard let session = selectedSession else { return }
        if isDemoMode { selectedModelLabel = option.name; return }
        do {
            _ = try await rpcClient.rpcAdapted("session/selectModel", args: ["request": [
                "sessionId": session.sessionId,
                "provider": option.provider,
                "model": option.model
            ]])
            selectedModelLabel = option.name
        } catch {
            errorMessage = "切换模型失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    func dismissArchiveUndo() {
        lastArchivedSession = nil
    }

    /// 撤销最近一次归档。
    @MainActor
    func undoArchive() async {
        guard let session = lastArchivedSession else { return }
        lastArchivedSession = nil
        if isDemoMode {
            archivedSessionIds.remove(session.sessionId)
            await loadSessions(silently: true)
            return
        }
        do {
            _ = try await rpcClient.rpcAdapted("workspace/unarchiveSession", args: ["request": ["sessionId": session.sessionId]])
            archivedSessionIds.remove(session.sessionId)
            await loadSessions(silently: true)
        } catch {
            errorMessage = "撤销归档失败：\(error.localizedDescription)"
        }
    }

    /// 置顶 / 取消置顶（服务端 workspace/pinSession，桌面端同步）。
    @MainActor
    func togglePin(_ session: PocketSession) async {
        let pinned = pinnedSessionIds.contains(session.sessionId)
        if isDemoMode {
            if pinned { pinnedSessionIds.removeAll { $0 == session.sessionId } }
            else { pinnedSessionIds.insert(session.sessionId, at: 0) }
            return
        }
        do {
            let endpoint = pinned ? "workspace/unpinSession" : "workspace/pinSession"
            let value = try await rpcClient.rpcAdapted(endpoint, args: ["request": ["sessionId": session.sessionId]])
            if let list = value["pinnedSessionIds"] as? [String] {
                pinnedSessionIds = list
            } else if pinned {
                pinnedSessionIds.removeAll { $0 == session.sessionId }
            } else {
                pinnedSessionIds.insert(session.sessionId, at: 0)
            }
        } catch {
            errorMessage = "置顶失败：\(error.localizedDescription)"
        }
    }

    /// 归档会话（从列表移除，桌面端同步隐藏）。
    @MainActor
    func archive(_ session: PocketSession) async {
        if isDemoMode {
            sessions.removeAll { $0.sessionId == session.sessionId }
            archivedSessionIds.insert(session.sessionId)
            pinnedSessionIds.removeAll { $0 == session.sessionId }
            return
        }
        do {
            let value = try await rpcClient.rpcAdapted("workspace/archiveSession", args: ["request": [
                "sessionId": session.sessionId,
                "stopActivity": false
            ]])
            if let ids = value["archivedSessionIds"] as? [String] {
                archivedSessionIds = Set(ids)
            } else {
                archivedSessionIds.insert(session.sessionId)
            }
            sessions.removeAll { $0.sessionId == session.sessionId }
            pinnedSessionIds.removeAll { $0 == session.sessionId }
            lastArchivedSession = session
            if selectedSession?.sessionId == session.sessionId { selectedSession = nil }
        } catch {
            errorMessage = "归档失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    func createSession() async {
        do {
            var request: [String: Any] = [:]
            if let initialized = try? await rpcClient.rpcAdapted("workspace/initializeDefault", args: [:]),
               let workspace = initialized["workspace"] as? [String: Any],
               let workspaceId = workspace["workspaceId"] as? String {
                request["workspaceId"] = workspaceId
            }
            let value = try await rpcClient.rpcAdapted("session/create", args: ["request": request])
            guard let id = value["sessionId"] as? String else { throw ConnectionError.invalidPayload }
            let session = PocketSession(sessionId: id, updatedAt: Date().timeIntervalSince1970, running: false, blank: true)
            await loadSessions()
            if !sessions.contains(where: { $0.sessionId == id }) { sessions.insert(session, at: 0) }
            open(session)
        } catch {
            errorMessage = "无法创建会话：\(error.localizedDescription)"
        }
    }

    /// 只保留最近打开过的几条会话内容，其余只留 ID（草稿另存在 DraftStore）。
    /// 原生不会把聊过的每条会话都摊在内存里；我们也别一直涨。
    @MainActor
    func trimRetainedConversations(keeping sessionId: String, limit: Int = ConversationCachePolicy.defaultLimit) {
        guard conversations.count > limit else { return }
        let active = activeConversation?.sessionId ?? sessionId
        let refs = conversations.values.map {
            CachedConversationRef(id: $0.sessionId, lastOpenedAt: $0.lastOpenedAt)
        }
        // 淘汰谁交给 DSHKit；当前会话和正在看的会话永不淘汰。
        let doomed = ConversationCachePolicy.evictions(from: refs,
                                                       keeping: [active, sessionId],
                                                       limit: limit)
        guard !doomed.isEmpty else { return }
        for id in doomed {
            guard let conversation = conversations[id] else { continue }
            conversation.liveTask?.cancel()
            conversation.fallbackTask?.cancel()
            conversation.coordinatorTask?.cancel()
            jobRoster.stop()
            conversations.removeValue(forKey: id)
        }
        recordDiagnostic("会话缓存回收 \(doomed.count) 条，剩 \(conversations.count) 条")
    }

    @MainActor
    /// 进入会话：只切状态、让界面立刻有内容；订阅与维护工作交给 startBackgroundFeeds。
    func open(_ session: PocketSession) {
        if isDemoMode { openDemo(session); return }
        if selectedSession?.sessionId == session.sessionId,
           activeConversation?.coordinatorStarted == true { return }

        // 切到独立会话实例：旧会话的实时流停止，状态留存在 conversations 里，不再写入新会话。
        if let current = activeConversation, current.sessionId != session.sessionId {
            current.liveTask?.cancel()
            current.fallbackTask?.cancel()
            current.coordinatorTask?.cancel()
            if let old = current.coordinator { Task { await old.stop() } }
            current.coordinatorStarted = false
        }
        liveTask?.cancel()
        fallbackTask?.cancel()

        let isNewConversation = conversations[session.sessionId] == nil
        let conversation = conversations[session.sessionId] ?? ConversationState(sessionId: session.sessionId)
        conversations[session.sessionId] = conversation
        conversation.lastOpenedAt = Date()
        activeConversation = conversation
        conversation.conversationToken = UUID()
        conversation.turnStarts.removeAll()
        conversation.turnEnds.removeAll()
        conversation.isLoadingConversation = false
        conversation.conversationError = nil
        // 打开时先用会话列表里的 running 状态（快照窗口可能不包含 turn/start 边界）。
        conversation.isTurnRunning = session.running
        conversation.turnStartedAt = session.running
            ? Self.dateFromSessionUpdatedAt(session.updatedAt)
            : nil
        conversation.hasMoreOlder = false
        conversation.isLoadingOlder = false
        conversation.olderAnchorID = nil
        conversation.liveTurnEventsSeen = false
        if isNewConversation {
            conversation.messages = []
            conversation.steps = []
            conversation.turnFailures = []
        }

        selectedSession = session
        // 可见会话归模型维护，视图不再写（通知直达等入口也能覆盖到）。
        visibleSessionId = session.sessionId
        markFinishedAwaitingRead(session.sessionId)
        liveConnection = .connecting
        // 未确认消息重新挂到该会话（发件箱兜底）；已有 messages 的会话保留历史。
        let outboxPending = restoreOutboxPending(for: session)
        for pending in outboxPending where !conversation.messages.contains(where: { $0.rpcId == pending.rpcId }) {
            conversation.messages.append(pending)
        }
        applyOutboxFlags(to: conversation, sessionId: session.sessionId)
        // 草稿图落盘过：空的就补回来（App 被杀后仍能接着发）。
        if conversation.draftImages.isEmpty {
            let restored = DraftImageStore.load(sessionId: session.sessionId)
            if !restored.isEmpty { conversation.draftImages = restored }
        }
        beginDiagnosticVisit(reusedMessages: isNewConversation ? 0 : conversation.messages.count)
        // 加载态由策略决定：有缓存就直接显示内容，不再转圈等快照。
        // 顺序很关键：先把计时起点设好，再按策略收尾，否则 noteLoadFinished 会直接返回（踩过）。
        let openPlan = ConversationOpenPlan.make(cachedMessageCount: conversation.messages.count)
        conversation.loadStartedAt = Date()
        conversation.loadTimingPending = true
        conversation.isLoadingConversation = !openPlan.skipLoadingState
        if openPlan.skipLoadingState, let source = openPlan.loadSource {
            noteLoadFinished(source: source, conversation: conversation)
        }
        requestScrollToBottom()

        // 首帧之后再起订阅与维护：进入路径上不做网络与清理工作。
        let showsLoading = !openPlan.skipLoadingState
        Task { @MainActor [weak self] in
            await self?.startBackgroundFeeds(for: conversation, session: session, showsLoading: showsLoading)
        }
    }

    /// 进入之后的订阅与维护（不在首帧同步路径上）。
    @MainActor
    func startBackgroundFeeds(for conversation: ConversationState, session: PocketSession,
                              showsLoading: Bool) async {
        guard activeConversation === conversation else { return }
        pruneStaleOutbox()
        recordDiagnostic("打开会话：\(session.displayTitle)")
        startDiagnosticSampler()
        trimRetainedConversations(keeping: session.sessionId)
        guard let client = syncClient else {
            // 地址异常时保留旧路径兜底。
            liveTask = Task { await loadConversation(session) }
            return
        }
        startCoordinator(for: conversation, session: session, client: client, showsLoading: showsLoading)
#if DEBUG
        let olderLoads = DebugLaunch.loadOlderCount
        if olderLoads > 0 {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                for _ in 0..<olderLoads {
                    self?.loadOlderMessages()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
#endif
    }

    @MainActor
    func loadConversation(_ session: PocketSession) async {
        isLoadingConversation = true
        // 历史上限走 HTTP 分页：公网隧道可能限制 WebSocket 单帧大小，
        // 不能只依赖 follow 的首帧快照。
        fallbackTask?.cancel()
        fallbackTask = Task { await pollLiveFallback(session) }
        let token = conversationToken
        let historyTask = Task { await self.loadHistory(session, token: token) }
        await follow(session)
        _ = await historyTask.value
        if activeConversation?.sessionId == session.sessionId,
           selectedSession?.sessionId == session.sessionId,
           isLoadingConversation {
            isLoadingConversation = false
        }
    }

    /// 实时流不可用（例如公网代理拒绝大帧）时，用 HTTP 分页轮询兜底，保证新消息仍能出现。
    @MainActor
    func pollLiveFallback(_ session: PocketSession) async {
        while !Task.isCancelled,
              activeConversation?.sessionId == session.sessionId,
              selectedSession?.sessionId == session.sessionId {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { break }
            guard activeConversation?.sessionId == session.sessionId,
                  selectedSession?.sessionId == session.sessionId else { return }
            let stalled = isTurnRunning && Date().timeIntervalSince(lastLiveFrameAt) > 15
            if !liveConnection.isConnected || stalled {
                await loadHistory(session)
            }
        }
    }

    @MainActor
    func loadHistory(_ session: PocketSession, token: UUID? = nil) async {
        do {
            let address: [String: Any] = ["kind": "session", "sessionId": session.sessionId]
            let page = try await rpcClient.rpcAdapted("session/page", args: ["request": ["address": address, "maxMessages": Self.conversationMessageLimit]])
            if let token, token != conversationToken { return }
            guard activeConversation?.sessionId == session.sessionId,
                  selectedSession?.sessionId == session.sessionId else { return }
            let wasEmpty = messages.isEmpty
            let records = page["records"] as? [[String: Any]] ?? []
            let history = records.compactMap(PocketMessage.init(record:))
            mergeMessages(history)
            mergeSteps(from: records)
            confirmInboxOutbox(in: records)
            isLoadingConversation = false
            if let conversation = activeConversation {
                noteLoadFinished(source: "session/page", conversation: conversation)
            }
            if wasEmpty { requestScrollToBottom() }
        } catch {
            if error is CancellationError { return }
            guard selectedSession?.sessionId == session.sessionId, messages.isEmpty else { return }
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            if let authError = error as? ConnectionError,
               case .server(let status) = authError,
               TimelineOrdering.isUnauthorized(statusCode: status) {
                handleAuthExpired()
                return
            }
            conversationError = "无法读取历史对话：\(error.localizedDescription)"
        }
    }

    @MainActor
    func mergeMessages(_ incoming: [PocketMessage]) {
        loadOutboxIfNeeded()
        var bySequence = Dictionary(uniqueKeysWithValues: messages.filter { !$0.isPending }.map { ($0.sequence, $0) })
        for message in incoming where !message.isPending { bySequence[message.sequence] = message }
        let incomingUserMessages = incoming.filter(\.isUser)
        let incomingRpcIds = Set(incoming.compactMap(\.rpcId).map { $0.lowercased() })
        confirmOutbox(rpcIds: incomingRpcIds)
        ackedSendRpcIds.subtract(incomingRpcIds)
        failedSendRpcIds.subtract(incomingRpcIds)
        activeConversation?.steeredRpcIds.subtract(incomingRpcIds)
        // 只用 rpcId 精确确认 pending。绝不能按“文本出现在历史里”来判断：
        // 用户发过同样内容的短消息（如“继续”）时，会把刚发出的 pending 误删，表现为消息发不出去。
        let previousMaxConfirmed = messages.filter { !$0.isPending }.map(\.sequence).max() ?? -1
        let latestIncomingUser = incomingUserMessages.max { $0.sequence < $1.sequence }
        let pending = messages.filter { message in
            guard message.isPending else { return false }
            if let rpcId = message.rpcId {
                // 兜底：服务端没回填 rpcId（steer 偶发丢确认），但本次新出现了同文本用户消息。
                if incoming.contains(where: {
                    $0.isUser && !$0.isPending && $0.rpcId == nil
                        && $0.text == message.text && $0.sequence > previousMaxConfirmed
                }) {
                    acknowledgedSendRpcIds.remove(rpcId)
                    confirmOutbox(rpcIds: [rpcId])
                    return false
                }
                let decision = TimelineOrdering.pendingDecision(
                    rpcId: rpcId,
                    hasRealMessageWithSameRpcId: incoming.contains {
                        !$0.isPending && $0.rpcId?.lowercased() == rpcId.lowercased()
                    },
                    acknowledgedInIncoming: incomingRpcIds.contains(rpcId.lowercased()),
                    isFailed: failedSendRpcIds.contains(rpcId),
                    inOutbox: outboxEntries.contains { $0.id.lowercased() == rpcId.lowercased() },
                    isAcknowledged: acknowledgedSendRpcIds.contains(rpcId)
                )
                switch decision {
                case .replaceWithReal:
                    acknowledgedSendRpcIds.remove(rpcId)
                    if failedSendRpcIds.remove(rpcId) != nil { conversationError = nil }
                    return false
                case .acknowledgeAndKeep:
                    acknowledgedSendRpcIds.insert(rpcId)
                    if failedSendRpcIds.remove(rpcId) != nil { conversationError = nil }
                    return true
                case .keep:
                    return true
                case .dropStale:
                    return false
                }
            }
            // 兼容不回 rpcId 的服务端：仅当“发送之后新出现的最后一条用户消息”文本相同才确认。
            if message.rpcId == nil,
               let latest = latestIncomingUser,
               latest.text == message.text,
               latest.sequence > previousMaxConfirmed {
                return false
            }
            return true
        }
        messages = (Array(bySequence.values) + pending).sorted { $0.sequence < $1.sequence }
        restoreMissingOutboxMessages()
        pruneStaleOutbox()
        timingLog("model_update incoming=\(incoming.count) total=\(messages.count)")
    }

    static func homeDirectory(for cwd: String) -> String {
        let parts = cwd.split(separator: "/").map(String.init)
        if parts.count >= 2, parts[0] == "Users" { return "/Users/\(parts[1])" }
        if parts.count >= 2, parts[0] == "home" { return "/home/\(parts[1])" }
        return "~"
    }

    /// 从历史记录里提取 steer 的 inbox rpcId（agent/inbox/spliced），用于确认发件箱。
    func inboxRpcIds(in records: [[String: Any]]) -> Set<String> {
        var ids = Set<String>()
        for record in records {
            guard let event = record["event"] as? [String: Any],
                  event["type"] as? String == "agent/inbox/spliced",
                  let data = event["data"] as? [String: Any],
                  let inserted = data["inserted"] as? [[String: Any]] else { continue }
            for item in inserted {
                if let rpcId = (item["source"] as? [String: Any])?["rpcId"] as? String, !rpcId.isEmpty {
                    ids.insert(rpcId.lowercased())
                }
            }
        }
        return ids
    }

    @MainActor
    func confirmInboxOutbox(in records: [[String: Any]]) {
        let ids = inboxRpcIds(in: records)
        guard !ids.isEmpty else { return }
        // 先登记为"已确认但消息体尚未落库"，mergeMessages 会保留本地 pending，
        // 等真实 user/message 出现再替换；否则消息会闪一下消失。
        acknowledgedSendRpcIds.formUnion(ids)
        confirmOutbox(rpcIds: ids)
        ackedSendRpcIds.subtract(ids)
        failedSendRpcIds.subtract(ids)
        if conversationError?.contains("服务端没有收到") == true { conversationError = nil }
        recordDiagnostic("历史中确认 steer 已送达（\(ids.count) 条）")
    }

    /// 不再按时间删除发件箱。未确认正文留到服务端历史确认，或用户取消发送。
    @MainActor
    func pruneStaleOutbox() {
        loadOutboxIfNeeded()
    }

    /// 消息展示排序键：服务端 seq 即唯一真相。
    /// 曾按 turn 区间把"生成中发送的用户消息"重排到本轮回复之后，但 steer 模式下这些消息
    /// 本身会打断当前轮、seq 就在回复之前；重排反而把用户消息和回复顺序弄反，故移除该启发式。
    func displaySortKey(for message: PocketMessage) -> Int {
        // 待发消息不能用 Int.max（会沉到「过程」行下面）；用发送时最后一条已确认消息的位置，
        // 这样它排在旧消息之后、发送之后产生的工具步骤之前。
        TimelineOrdering.sortKey(sequence: message.sequence,
                                 localSortKey: message.localSortKey,
                                 isPending: message.isPending)
    }
}
