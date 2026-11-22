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
        // 进入任何会话（包括退出后重进同一个）都先把「上一个活跃会话」的旧历史卸载。
        //
        // 为什么放在这里而不是 ConversationView.onDisappear：
        // NavigationStack 返回时视图的 onDisappear 实测不触发，`leave()` 也就不会跑——
        // 结果是内存看着降了（视图销毁），messages 数组其实还留着，重进又全量回来。
        // `open()` 是进入会话的唯一必经之路，必定执行。
        if let previous = activeConversation {
            let before = previous.messages.count
            previous.trimMessages(to: Self.retainedMessageLimit)
            if before != previous.messages.count {
                DiagFileLog.log("open-trim-previous \(before) -> \(previous.messages.count)")
            }
        }
        if isDemoMode { openDemo(session); return }
        if sessionStore.selected?.sessionId == session.sessionId,
           activeConversation?.coordinatorStarted == true { return }

        // 切到独立会话实例：旧会话的实时流停止，状态留存在 sessionStore.conversations 里，不再写入新会话。
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
        await runLiveStream(sessionId: session.sessionId)
        _ = await historyTask.value
        if activeConversation?.sessionId == session.sessionId,
           sessionStore.selected?.sessionId == session.sessionId,
           isLoadingConversation {
            isLoadingConversation = false
        }
    }

    /// 实时流不可用（例如公网代理拒绝大帧）时，用 HTTP 分页轮询兜底，保证新消息仍能出现。
    @MainActor
    func pollLiveFallback(_ session: PocketSession) async {
        while !Task.isCancelled,
              activeConversation?.sessionId == session.sessionId,
              sessionStore.selected?.sessionId == session.sessionId {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { break }
            guard activeConversation?.sessionId == session.sessionId,
                  sessionStore.selected?.sessionId == session.sessionId else { return }
            // 假死判定**不能只在生成中生效**：
            // 发消息时 isTurnRunning 往往还是 false，此时实时流若已假死，
            // 既不会拉历史也不会重连，消息就卡在「发送中」直到 HTTP 重试跑完
            // （真机实测：pending 1 卡了 50 秒，同期 Live Signal 显示 2 分钟无帧）。
            let silentSeconds = Date().timeIntervalSince(lastLiveFrameAt)
            let stalled = silentSeconds > 30
            if stalled {
                recordDiagnostic("实时流假死：\(Int(silentSeconds)) 秒无帧，尝试恢复")
            }
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
                  sessionStore.selected?.sessionId == session.sessionId else { return }
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
            guard sessionStore.selected?.sessionId == session.sessionId, messages.isEmpty else { return }
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
        // 会话内允许上滑翻历史，所以不按「退出后保留量」裁；
        // 但仍有会话内上限，避免 400 轮那种情况把内存吃到 1.5 GB。
        // 不在这里裁：裁剪方向取决于「这批消息是哪来的」——
        // 上滑加载要保历史（裁最新），新消息/快照要保最新（裁最旧）。
        // 统一在这里裁会先剪掉刚加载的更早消息（表现为 Last load = ok +0）。
        restoreMissingOutboxMessages()
        pruneStaleOutbox()
        timingLog("model_update incoming=\(incoming.count) total=\(messages.count)")
    }

    /// 把消息裁到「最近 N 条」。
    ///
    /// 优先丢最旧的已确认消息，pending（正在发送的）一律保留。
    /// 裁掉消息后，属于它们的步骤和失败记录也一起裁，避免这些行仍然被渲染。
    @MainActor
    func trimToRetentionLimit() {
        trimMessages(to: Self.retainedMessageLimit)
    }

    /// 会话内上限：允许翻历史，但不让消息无限累积（超了会 OOM）。
    @MainActor
    func trimToInSessionLimit() {
        trimMessages(to: Self.inSessionMessageLimit)
    }

    @MainActor
    private func trimMessages(to limit: Int) {
        guard messages.count > limit else { return }
        var remaining = messages
        var removed = 0
        var index = 0
        let target = messages.count - limit
        while removed < target, index < remaining.count {
            if remaining[index].isPending {
                index += 1
            } else {
                remaining.remove(at: index)
                removed += 1
            }
        }
        guard removed > 0 else { return }
        messages = remaining
        let oldestKept = remaining.first?.sequence ?? Int.max
        steps = steps.filter { $0.sequence >= oldestKept }
        if let conversation = activeConversation {
            conversation.turnFailures = conversation.turnFailures.filter { $0.sequence >= oldestKept }
        }
        // 裁剪发生时把 hasMoreOlder 置为 true：
        // 本地还有没卸载的更早消息 ⇒ 上滑应该能请求。
        // 服务端只在请求分页后才回 hasMore，而请求又被这个开关挡着——
        // 旧写法形成死循环：初始 false → 不请求 → 永远 false（2026-11-22 用户反馈）。
        // 服务端若回 hasMore=false，.hasMore 分支会改回来，不会无限请求。
        hasMoreOlder = true
        recordDiagnostic("消息裁剪：丢弃 \(removed) 条，保留 \(remaining.count) 条（limit=\(limit)，hasMore 置 true）")
    }
}

extension ConnectionModel {
    /// 把同一个 turn 里连续的助手消息合并成一条。
    ///
    /// 边界规则（方案 A）：只看 turn 是否相同，不看中间有没有工具过程——
    /// 因为过程行已经不再展示，turn 就是唯一的「一轮问答」边界。
    /// 用户消息、待发消息永远不参与合并。
    static func mergeByTurn(_ messages: [PocketMessage]) -> [PocketMessage] {
        var result: [PocketMessage] = []
        var buffer: [PocketMessage] = []
        var bufferTurn: Int?

        func flush() {
            guard let first = buffer.first else { return }
            if buffer.count == 1 {
                result.append(first)
            } else {
                let merged = PocketMessage(sequence: first.sequence,
                                           kind: first.kind,
                                           text: buffer.map(\.text).filter { !$0.isEmpty }
                                               .joined(separator: "\n\n"),
                                           isUser: false,
                                           rpcId: nil,
                                           images: buffer.flatMap(\.images),
                                           turn: bufferTurn)
                result.append(merged)
            }
            buffer.removeAll()
            bufferTurn = nil
        }

        for message in messages {
            guard !message.isUser, !message.isPending, let turn = message.turn else {
                flush()
                result.append(message)
                continue
            }
            if bufferTurn == turn {
                buffer.append(message)
            } else {
                flush()
                buffer = [message]
                bufferTurn = turn
            }
        }
        flush()
        return result
    }
}
