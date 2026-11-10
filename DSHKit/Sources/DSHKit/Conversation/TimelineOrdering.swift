import Foundation

/// 待发消息在合并历史时的处理决定。
public enum PendingDecision: Equatable, Sendable {
    /// 真实消息（带同一 rpcId）已进历史，用真实消息替换本地气泡。
    case replaceWithReal
    /// 服务端只 ACK 了 rpcId，消息体尚未落库：保留气泡，等历史刷新。
    case acknowledgeAndKeep
    /// 发件箱已清理且没有任何在途标记：历史遗留气泡，丢弃。
    case dropStale
    /// 仍在发件箱 / 已确认待落库 / 失败待重试：保留。
    case keep
}

/// 对话时间线的纯逻辑（不依赖 UI、网络、存储），供 App 与单元测试共用。
public enum TimelineOrdering {
    /// 待发消息的排序锚点：发送时刻已知的最大序号（消息与工具步骤取最大）。
    public static func pendingAnchor(messageMax: Int, stepMax: Int) -> Int {
        max(messageMax, stepMax)
    }

    /// 时间线排序键：待发消息用本地锚点，已确认消息用服务端序号。
    public static func sortKey(sequence: Int, localSortKey: Int?, isPending: Bool) -> Int {
        isPending ? (localSortKey ?? sequence) : sequence
    }

    /// 合并历史时如何处置一条本地待发消息。
    /// - Parameters:
    ///   - rpcId: 待发消息的 requestId；nil 表示服务端不回填 rpcId 的兼容路径。
    ///   - hasRealMessageWithSameRpcId: 本次 incoming 中是否已有同 rpcId 的真实消息。
    ///   - acknowledgedInIncoming: 本次 incoming 是否包含该 rpcId 的 ACK。
    ///   - isFailed: 是否已标记发送失败（需要保留气泡让用户重试）。
    ///   - inOutbox: 是否仍在本地发件箱。
    ///   - isAcknowledged: 是否已 ACK、正在等待消息落库。
    public static func pendingDecision(
        rpcId: String?,
        hasRealMessageWithSameRpcId: Bool,
        acknowledgedInIncoming: Bool,
        isFailed: Bool,
        inOutbox: Bool,
        isAcknowledged: Bool
    ) -> PendingDecision {
        guard let rpcId, !rpcId.isEmpty else {
            // 无 rpcId 的兼容路径由调用方按文本兜底匹配，这里默认保留。
            return .keep
        }
        if hasRealMessageWithSameRpcId { return .replaceWithReal }
        if acknowledgedInIncoming { return .acknowledgeAndKeep }
        if isFailed { return .keep }
        if inOutbox || isAcknowledged { return .keep }
        return .dropStale
    }

    public static func isUnauthorized(statusCode: Int) -> Bool {
        statusCode == 401
    }
}
