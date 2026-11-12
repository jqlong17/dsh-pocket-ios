// SessionStore

import Foundation
import Observation

/// 会话列表、当前会话、以及按 sessionId 留在内存里的对话缓存。
///
/// 边界（spec/12）：
/// - 只持有「有哪些会话、现在看的是哪一条、缓存里还留着什么」；
/// - 不发网络、不拼 RPC。拉列表、打开、淘汰仍由 ConnectionModel 编排，通过本类型读写。
/// - `messages` / `steps` 仍从 `active` 派生，不在这里再存一份。
@Observable
final class SessionStore {
    var sessions: [PocketSession] = []
    var archivedSessionIds: Set<String> = []
    /// 置顶会话（服务端返回顺序：最近置顶在前）。
    var pinnedSessionIds: [String] = []
    var isLoadingSessions = false
    /// 列表拉取失败后的自动重试。
    var retryTask: Task<Void, Never>?
    var selected: PocketSession?
    var navigationPath: [PocketSession] = []
    /// 按 sessionId 留存的对话。切换会话不丢，淘汰由调用方按策略做。
    var conversations: [String: ConversationState] = [:]
    var active: ConversationState?
}

extension SessionStore {
    /// 切换到一条会话：只做**纯状态**（查/建缓存、重置时间线标记、设为当前）。
    /// 取消旧流、恢复发件箱、启动订阅这些编排动作留在 ConnectionModel。
    ///
    /// - Returns: 该会话的状态对象，以及是不是第一次打开。
    @discardableResult
    func activate(_ session: PocketSession, now: Date = Date()) -> (conversation: ConversationState, isNew: Bool) {
        let isNew = conversations[session.sessionId] == nil
        let conversation = conversations[session.sessionId] ?? ConversationState(sessionId: session.sessionId)
        conversations[session.sessionId] = conversation
        conversation.lastOpenedAt = now
        active = conversation
        conversation.conversationToken = UUID()
        conversation.turnStarts.removeAll()
        conversation.turnEnds.removeAll()
        conversation.isLoadingConversation = false
        conversation.conversationError = nil
        // 打开时先用列表里的 running 状态：快照窗口可能不包含 turn/start 边界。
        conversation.isTurnRunning = session.running
        conversation.turnStartedAt = session.running ? Self.updatedAt(session.updatedAt) : nil
        conversation.hasMoreOlder = false
        conversation.isLoadingOlder = false
        conversation.olderAnchorID = nil
        conversation.liveTurnEventsSeen = false
        if isNew {
            conversation.messages = []
            conversation.steps = []
            conversation.turnFailures = []
        }
        selected = session
        return (conversation, isNew)
    }

    /// 列表的 updatedAt 可能是毫秒或秒。
    static func updatedAt(_ value: TimeInterval) -> Date {
        let seconds = value > 10_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }
}
