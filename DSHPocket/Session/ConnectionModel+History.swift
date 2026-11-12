// 会话历史

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

/// 打开会话与历史装载：拉分页、合并消息、恢复发件箱气泡、起后台任务。
///
/// 从 ConnectionModel+Sessions 拆出来（按行号整段搬迁，避免注释块粘连）：
/// 「列表」是会话维度的增删改查，「历史」是单个会话的消息装载，两者独立演化。
extension ConnectionModel {

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

        // 纯状态切换在 SessionStore（可单测）；这里只负责取消旧流与后续编排。
        let (conversation, isNewConversation) = sessionStore.activate(session)
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
            if let authError = error as? ConnectionError, authError.isUnauthorized {
                handleAuthExpired()
                return
            }
            conversationError = "无法读取历史对话：\(error.localizedDescription)"
        }
    }

    @MainActor
    func mergeMessages(_ incoming: [PocketMessage]) {
        loadOutboxIfNeeded()
        var bySequence = Dictionary(messages.filter { !$0.isPending }.map { ($0.sequence, $0) }, uniquingKeysWith: { first, _ in first })
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
}
