import Foundation

/// 时间线的排序键：只保留排序需要的最小信息，与具体消息类型解耦。
///
/// 为什么单独抽出来：排序规则里有三条容易写错的约定（同键按 seq、pending 优先、
/// 同一轮内按本地发送顺序），放在视图里既无法测试也不该由视图决定。
public struct TimelineSortKey: Equatable, Sendable {
    public var id: String
    public var sortKey: Int
    public var sequence: Int
    /// 是否是一条消息（过程行、失败卡片为 false）。
    public var isMessage: Bool
    /// 消息是否还在本地待确认。
    public var isPending: Bool
    /// 本地发送顺序（毫秒），只用于两条都在等发送时的先后。
    public var localOrder: Int

    public init(id: String, sortKey: Int, sequence: Int,
                isMessage: Bool, isPending: Bool = false, localOrder: Int = 0) {
        self.id = id
        self.sortKey = sortKey
        self.sequence = sequence
        self.isMessage = isMessage
        self.isPending = isPending
        self.localOrder = localOrder
    }
}

public enum TimelineAssembly {
    /// 稳定排序：同一条键相同的元素按 id 兜底，保证渲染顺序可复现。
    public static func ordered(_ items: [TimelineSortKey]) -> [TimelineSortKey] {
        items.sorted { lhs, rhs in
            if lhs.sortKey != rhs.sortKey { return lhs.sortKey < rhs.sortKey }
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            if lhs.isMessage && rhs.isMessage {
                if lhs.isPending != rhs.isPending { return lhs.isPending }
                if lhs.localOrder != rhs.localOrder { return lhs.localOrder < rhs.localOrder }
                return lhs.id < rhs.id
            }
            if lhs.isMessage != rhs.isMessage { return lhs.isMessage }
            return lhs.id < rhs.id
        }
    }
}
