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
