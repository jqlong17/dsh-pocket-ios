import Foundation

/// turn 区间（模块 03）：用于把"生成中排队发送"的消息排到本轮回复之后。
public struct TurnRange: Equatable, Sendable {
    public let turn: Int
    public let startSeq: Int
    public let endSeq: Int?

    public init(turn: Int, startSeq: Int, endSeq: Int?) {
        self.turn = turn
        self.startSeq = startSeq
        self.endSeq = endSeq
    }
}

public struct OrderableMessage: Equatable, Sendable {
    public let id: String
    public let sequence: Int
    public let isUser: Bool
    public let isPending: Bool
    public let rpcId: String?

    public init(id: String, sequence: Int, isUser: Bool, isPending: Bool = false, rpcId: String? = nil) {
        self.id = id
        self.sequence = sequence
        self.isUser = isUser
        self.isPending = isPending
        self.rpcId = rpcId
    }
}

/// 展示排序：服务端 seq 为基准；落在 turn 区间内的用户消息（排队发送）排到该轮结束之后；
/// 同一 turn 内按原始 seq 二级排序；pending 永远在末尾。
public enum MessageOrdering {
    public static func displayKey(for message: OrderableMessage, turns: [TurnRange]) -> Int {
        guard message.isUser, !message.isPending else { return message.sequence }
        for range in turns {
            let end = range.endSeq ?? Int.max
            if message.sequence > range.startSeq, message.sequence < end {
                return end
            }
        }
        return message.sequence
    }

    public static func sorted(_ messages: [OrderableMessage], turns: [TurnRange]) -> [OrderableMessage] {
        messages.sorted { lhs, rhs in
            let leftKey = displayKey(for: lhs, turns: turns)
            let rightKey = displayKey(for: rhs, turns: turns)
            if leftKey != rightKey { return leftKey < rightKey }
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            if lhs.isPending != rhs.isPending { return !lhs.isPending }
            return lhs.id < rhs.id
        }
    }
}
