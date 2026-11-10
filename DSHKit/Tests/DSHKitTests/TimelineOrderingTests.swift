import Testing
@testable import DSHKit

@Suite("对话时间线排序与待发消息保留")
struct TimelineOrderingTests {
    @Test("待发消息锚点取消息与过程步骤的最大序号")
    func pendingAnchorUsesMaxOfMessagesAndSteps() {
        #expect(TimelineOrdering.pendingAnchor(messageMax: 10, stepMax: 14) == 14)
        #expect(TimelineOrdering.pendingAnchor(messageMax: 20, stepMax: 3) == 20)
        #expect(TimelineOrdering.pendingAnchor(messageMax: -1, stepMax: -1) == -1)
    }

    @Test("待发消息用本地锚点，已确认消息用服务端序号")
    func sortKeyPrefersLocalAnchorForPending() {
        #expect(TimelineOrdering.sortKey(sequence: Int.max, localSortKey: 12, isPending: true) == 12)
        #expect(TimelineOrdering.sortKey(sequence: 15, localSortKey: nil, isPending: true) == 15)
        #expect(TimelineOrdering.sortKey(sequence: 9, localSortKey: 99, isPending: false) == 9)
    }

    @Test("真实消息已进历史 → 用真实消息替换待发气泡")
    func replaceWhenRealMessageArrives() {
        #expect(TimelineOrdering.pendingDecision(
            rpcId: "abc", hasRealMessageWithSameRpcId: true,
            acknowledgedInIncoming: true, isFailed: false, inOutbox: true, isAcknowledged: false
        ) == .replaceWithReal)
    }

    @Test("只有 ACK、消息体未落库 → 保留气泡（修复‘消息被吞’）")
    func keepOnAckWithoutMessageBody() {
        #expect(TimelineOrdering.pendingDecision(
            rpcId: "abc", hasRealMessageWithSameRpcId: false,
            acknowledgedInIncoming: true, isFailed: false, inOutbox: false, isAcknowledged: false
        ) == .acknowledgeAndKeep)
    }

    @Test("发件箱已清理但已登记 ACK → 继续保留，等消息落库")
    func keepAcknowledgedPendingAfterOutboxCleanup() {
        #expect(TimelineOrdering.pendingDecision(
            rpcId: "abc", hasRealMessageWithSameRpcId: false,
            acknowledgedInIncoming: false, isFailed: false, inOutbox: false, isAcknowledged: true
        ) == .keep)
    }

    @Test("仍在发件箱 → 保留")
    func keepWhileStillInOutbox() {
        #expect(TimelineOrdering.pendingDecision(
            rpcId: "abc", hasRealMessageWithSameRpcId: false,
            acknowledgedInIncoming: false, isFailed: false, inOutbox: true, isAcknowledged: false
        ) == .keep)
    }

    @Test("发送失败 → 保留气泡供重试")
    func keepFailedPending() {
        #expect(TimelineOrdering.pendingDecision(
            rpcId: "abc", hasRealMessageWithSameRpcId: false,
            acknowledgedInIncoming: false, isFailed: true, inOutbox: false, isAcknowledged: false
        ) == .keep)
    }

    @Test("无任何在途标记 → 视为历史遗留并丢弃")
    func dropStalePending() {
        #expect(TimelineOrdering.pendingDecision(
            rpcId: "abc", hasRealMessageWithSameRpcId: false,
            acknowledgedInIncoming: false, isFailed: false, inOutbox: false, isAcknowledged: false
        ) == .dropStale)
    }

    @Test("无 rpcId 的兼容消息默认保留，由文本兜底匹配")
    func keepMessagesWithoutRpcId() {
        #expect(TimelineOrdering.pendingDecision(
            rpcId: nil, hasRealMessageWithSameRpcId: false,
            acknowledgedInIncoming: false, isFailed: false, inOutbox: false, isAcknowledged: false
        ) == .keep)
    }

    @Test("401 判定")
    func unauthorizedClassifier() {
        #expect(TimelineOrdering.isUnauthorized(statusCode: 401))
        #expect(!TimelineOrdering.isUnauthorized(statusCode: 403))
        #expect(!TimelineOrdering.isUnauthorized(statusCode: 200))
    }
}
