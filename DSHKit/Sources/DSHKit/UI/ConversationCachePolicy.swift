import Foundation

/// 进会话前的一个决定：还要不要走 HTTP 基线。
public enum SessionOpenPolicy {
    /// 消息已经在内存里就不再拉整页，只靠 WS 快照补齐。
    public static func shouldFetchHTTPBaseline(cachedMessageCount: Int) -> Bool {
        cachedMessageCount == 0
    }
}

/// 内存里的会话副本引用，只留判定需要的最小信息。
public struct CachedConversationRef: Equatable {
    public let id: String
    public let lastOpenedAt: Date

    public init(id: String, lastOpenedAt: Date) {
        self.id = id
        self.lastOpenedAt = lastOpenedAt
    }
}

/// 会话副本能留几条。
///
/// 原生不会把聊过的每条会话都摊在内存里；超出的按最近打开时间淘汰。
public enum ConversationCachePolicy {
    public static let defaultLimit = 3

    /// 返回要丢掉的会话 id。`pinned`（当前会话、正在看的会话）永不淘汰。
    public static func evictions(from refs: [CachedConversationRef],
                                 keeping pinned: Set<String>,
                                 limit: Int = defaultLimit) -> [String] {
        guard refs.count > limit else { return [] }
        let overflow = refs.count - limit
        let candidates = refs
            .filter { !pinned.contains($0.id) }
            .sorted { $0.lastOpenedAt < $1.lastOpenedAt }
        return candidates.prefix(overflow).map(\.id)
    }
}
