import Foundation

/// 待确认消息（pending）的对账规则（模块 03）。
public struct PendingCandidate: Equatable, Sendable {
    public let rpcId: String?
    public let text: String
    public let sequence: Int

    public init(rpcId: String?, text: String, sequence: Int = Int.max) {
        self.rpcId = rpcId
        self.text = text
        self.sequence = sequence
    }
}

public enum PendingReconciler {
    /// 是否保留该 pending。
    /// - 有 rpcId：只有服务端确认（incomingRpcIds）才移除；失败待重发或仍在发件箱才保留。
    /// - 无 rpcId（老服务端）：仅当"发送之后新出现的最后一条用户消息"文本相同才视为确认。
    /// 绝不能"文本出现在历史里就移除"（会把同文本的新消息误删）。
    public static func shouldKeep(_ pending: PendingCandidate,
                                  incomingRpcIds: Set<String>,
                                  outboxRpcIds: Set<String>,
                                  failedRpcIds: Set<String>,
                                  latestIncomingUserText: String?,
                                  latestIncomingUserSeq: Int?,
                                  previousMaxConfirmedSeq: Int) -> Bool {
        if let rpcId = pending.rpcId {
            if incomingRpcIds.contains(where: { RPCId.matches($0, rpcId) }) { return false }
            if failedRpcIds.contains(where: { RPCId.matches($0, rpcId) }) { return true }
            return outboxRpcIds.contains(where: { RPCId.matches($0, rpcId) })
        }
        guard let text = latestIncomingUserText, let seq = latestIncomingUserSeq else { return true }
        if text == pending.text && seq > previousMaxConfirmedSeq { return false }
        return true
    }
}
