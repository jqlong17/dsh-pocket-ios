// ConnectionModel+Facade

import Foundation
import DSHKit

/// ConnectionModel 的「转发层」。
///
/// 这些属性本身不存状态，只是把 `activeConversation` / `diagnostics` / `outbox` 的字段
/// 以主模型的属性名暴露出去，让调用点不必写长链。
///
/// 单独成文件的原因：主文件已经 690 行（app 阈值 600），而这些转发一处逻辑也没有，
/// 混在里面会让「状态定义」和「视图方便方法」看起来一样重。
extension ConnectionModel {
    var activeSessionId: String? { activeConversation?.sessionId }

    var messages: [PocketMessage] {
        get { activeConversation?.messages ?? [] }
        set { activeConversation?.messages = newValue }
    }
    var steps: [PocketStep] {
        get { activeConversation?.steps ?? [] }
        set { activeConversation?.steps = newValue }
    }
    var turnFailures: [TurnFailureNotice] {
        get { activeConversation?.turnFailures ?? [] }
        set { activeConversation?.turnFailures = newValue }
    }
    var jobs: [PocketJob] {
        get { activeConversation?.jobs ?? [] }
        set { activeConversation?.jobs = newValue }
    }
    /// 还在跑的（running / stopping）。
    var runningJobs: [PocketJob] { jobs.filter(\.isRunning) }
    var isLoadingConversation: Bool {
        get { activeConversation?.isLoadingConversation ?? false }
        set { activeConversation?.isLoadingConversation = newValue }
    }
    var conversationError: String? {
        get { activeConversation?.conversationError }
        set { activeConversation?.conversationError = newValue }
    }
    var isTurnRunning: Bool {
        get { activeConversation?.isTurnRunning ?? false }
        set { activeConversation?.isTurnRunning = newValue }
    }
    var turnStartedAt: Date? {
        get { activeConversation?.turnStartedAt }
        set { activeConversation?.turnStartedAt = newValue }
    }
    var scrollToBottomTick: Int {
        get { activeConversation?.scrollToBottomTick ?? 0 }
        set { activeConversation?.scrollToBottomTick = newValue }
    }
    var lastLiveFrameAt: Date {
        get { activeConversation?.lastLiveFrameAt ?? Date() }
        set { activeConversation?.lastLiveFrameAt = newValue }
    }
    var hasMoreOlder: Bool {
        get { activeConversation?.hasMoreOlder ?? false }
        set { activeConversation?.hasMoreOlder = newValue }
    }
    var isLoadingOlder: Bool {
        get { activeConversation?.isLoadingOlder ?? false }
        set { activeConversation?.isLoadingOlder = newValue }
    }
    var olderAnchorID: String? {
        get { activeConversation?.olderAnchorID }
        set { activeConversation?.olderAnchorID = newValue }
    }
    var olderLoadTick: Int {
        get { activeConversation?.olderLoadTick ?? 0 }
        set { activeConversation?.olderLoadTick = newValue }
    }
    var liveTurnEventsSeen: Bool {
        get { activeConversation?.liveTurnEventsSeen ?? false }
        set { activeConversation?.liveTurnEventsSeen = newValue }
    }
    var pendingQuestion: PendingUserQuestion? {
        get { activeConversation?.pendingQuestion }
        set { activeConversation?.pendingQuestion = newValue }
    }

    var diagnosticSamples: [DiagnosticSample] { diagnostics.samples }
    var diagnosticVisits: [DiagnosticVisit] { diagnostics.visits }
    var liveConnectionState: String { liveConnection.label }
    var liveDiagnosticHistory: [String] { diagnostics.history }
    var liveTask: Task<Void, Never>? {
        get { activeConversation?.liveTask }
        set { activeConversation?.liveTask = newValue }
    }
    var fallbackTask: Task<Void, Never>? {
        get { activeConversation?.fallbackTask }
        set { activeConversation?.fallbackTask = newValue }
    }

    /// 发送状态（按会话隔离）：已确认（服务端受理、等待处理）/ 失败（可重发）。
    var ackedSendRpcIds: Set<String> {
        get { activeConversation?.ackedRpcIds ?? [] }
        set { activeConversation?.ackedRpcIds = newValue }
    }
    var failedSendRpcIds: Set<String> {
        get { activeConversation?.failedRpcIds ?? [] }
        set { activeConversation?.failedRpcIds = newValue }
    }
    /// 当前会话里、断网暂存等待一并发送的 rpcId。权威记录在发件箱的 heldOffline，这里只供打开中的会话显示。
    var queuedSendRpcIds: Set<String> {
        get { activeConversation?.queuedRpcIds ?? [] }
        set { activeConversation?.queuedRpcIds = newValue }
    }
    /// 已 ACK、等待消息落库的 rpcId（保留本地 pending，避免消息被吞）。
    var acknowledgedSendRpcIds: Set<String> {
        get { activeConversation?.acknowledgedRpcIds ?? [] }
        set { activeConversation?.acknowledgedRpcIds = newValue }
    }

    var outboxEntries: [OutboxEntry] { outbox.entries }
    var outboxLoaded: Bool { outbox.loaded }

    /// 派生：所有主机的地址合集。
    /// 保留这个名字是为了让连接/探针/自动选路这些既有代码不用一次性全改——
    /// 它们仍然按「地址」工作，只是地址的来源变成了 hosts。
    var savedEndpoints: [SavedEndpoint] { hosts.flatMap(\.endpoints) }

    /// 当前主机自己的地址（自动选路必须限定在这里，不能跨主机跳）。
    var currentHostEndpoints: [SavedEndpoint] {
        hosts.first { $0.id == currentHostId }?.endpoints ?? savedEndpoints
    }

    func persistHosts() {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: Self.hostsKey)
        }
    }
    /// 已完成、等待用户回复的会话（红点）。持久化，打开会话后清除。

}
