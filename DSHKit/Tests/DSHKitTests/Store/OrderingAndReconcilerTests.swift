import XCTest
@testable import DSHKit

final class OrderingAndReconcilerTests: XCTestCase {
    // M30：普通消息按 seq
    func testPlainMessagesSortedBySequence() {
        let messages = [
            OrderableMessage(id: "b", sequence: 20, isUser: true),
            OrderableMessage(id: "a", sequence: 10, isUser: false)
        ]
        XCTAssertEqual(MessageOrdering.sorted(messages, turns: []).map(\.id), ["a", "b"])
    }

    // M31：排队消息排到 turn 之后
    func testQueuedMessageMovesAfterTurnEnd() {
        let turns = [TurnRange(turn: 1, startSeq: 10, endSeq: 40)]
        let messages = [
            OrderableMessage(id: "turn-reply", sequence: 35, isUser: false),
            OrderableMessage(id: "queued", sequence: 20, isUser: true),
            OrderableMessage(id: "next-turn-reply", sequence: 60, isUser: false)
        ]
        XCTAssertEqual(MessageOrdering.sorted(messages, turns: turns).map(\.id),
                       ["turn-reply", "queued", "next-turn-reply"])
    }

    // M32：同一 turn 内多条排队消息按原始 seq 排序
    func testMultipleQueuedMessagesKeepOriginalOrder() {
        let turns = [TurnRange(turn: 1, startSeq: 10, endSeq: 40)]
        let messages = [
            OrderableMessage(id: "q2", sequence: 30, isUser: true),
            OrderableMessage(id: "q1", sequence: 20, isUser: true),
            OrderableMessage(id: "reply", sequence: 35, isUser: false)
        ]
        XCTAssertEqual(MessageOrdering.sorted(messages, turns: turns).map(\.id),
                       ["reply", "q1", "q2"])
    }

    // M33：pending 永远末尾
    func testPendingAlwaysLast() {
        let messages = [
            OrderableMessage(id: "pending", sequence: Int.max, isUser: true, isPending: true),
            OrderableMessage(id: "newer", sequence: 99, isUser: false)
        ]
        XCTAssertEqual(MessageOrdering.sorted(messages, turns: []).map(\.id), ["newer", "pending"])
    }

    // M10：同文本旧消息不会误删新 pending
    func testSameTextInHistoryDoesNotDropPending() {
        let keep = PendingReconciler.shouldKeep(
            PendingCandidate(rpcId: "new-rpc", text: "继续"),
            incomingRpcIds: [],
            outboxRpcIds: ["new-rpc"],
            failedRpcIds: [],
            latestIncomingUserText: "继续",   // 历史里有同文本旧消息
            latestIncomingUserSeq: 5,
            previousMaxConfirmedSeq: 100
        )
        XCTAssertTrue(keep)
    }

    // M11：老服务端无 rpcId，仅"发送之后最后一条同文本"可确认
    func testLegacyFallbackConfirmByLatestTextOnlyAfterSend() {
        let confirmed = PendingReconciler.shouldKeep(
            PendingCandidate(rpcId: nil, text: "继续"),
            incomingRpcIds: [], outboxRpcIds: [], failedRpcIds: [],
            latestIncomingUserText: "继续", latestIncomingUserSeq: 120,
            previousMaxConfirmedSeq: 100
        )
        XCTAssertFalse(confirmed)

        let old = PendingReconciler.shouldKeep(
            PendingCandidate(rpcId: nil, text: "继续"),
            incomingRpcIds: [], outboxRpcIds: [], failedRpcIds: [],
            latestIncomingUserText: "继续", latestIncomingUserSeq: 50,
            previousMaxConfirmedSeq: 100
        )
        XCTAssertTrue(old)
    }

    // M12/M13：rpcId 匹配才确认；不在发件箱的旧 pending 清理
    func testRpcIdReconciliationAndStaleCleanup() {
        let confirmed = PendingReconciler.shouldKeep(
            PendingCandidate(rpcId: "r1", text: "x"),
            incomingRpcIds: ["r1"], outboxRpcIds: ["r1"], failedRpcIds: [],
            latestIncomingUserText: nil, latestIncomingUserSeq: nil, previousMaxConfirmedSeq: 0
        )
        XCTAssertFalse(confirmed)

        let stale = PendingReconciler.shouldKeep(
            PendingCandidate(rpcId: "r2", text: "y"),
            incomingRpcIds: [], outboxRpcIds: [], failedRpcIds: [],
            latestIncomingUserText: nil, latestIncomingUserSeq: nil, previousMaxConfirmedSeq: 0
        )
        XCTAssertFalse(stale)

        let failed = PendingReconciler.shouldKeep(
            PendingCandidate(rpcId: "r3", text: "z"),
            incomingRpcIds: [], outboxRpcIds: [], failedRpcIds: ["r3"],
            latestIncomingUserText: nil, latestIncomingUserSeq: nil, previousMaxConfirmedSeq: 0
        )
        XCTAssertTrue(failed)
    }

    func testOpenTurnQueuesToMaxAndTieBreak() {
        let turns = [TurnRange(turn: 2, startSeq: 10, endSeq: nil)]
        let queued = OrderableMessage(id: "queued", sequence: 15, isUser: true)
        XCTAssertEqual(MessageOrdering.displayKey(for: queued, turns: turns), Int.max)

        let sameSeqA = OrderableMessage(id: "a", sequence: 5, isUser: false)
        let sameSeqPending = OrderableMessage(id: "p", sequence: 5, isUser: true, isPending: true)
        XCTAssertEqual(MessageOrdering.sorted([sameSeqPending, sameSeqA], turns: []).map(\.id), ["a", "p"])
    }

    func testReconcilerKeepsWhenNoIncomingInfo() {
        let keep = PendingReconciler.shouldKeep(
            PendingCandidate(rpcId: nil, text: "x"),
            incomingRpcIds: [], outboxRpcIds: [], failedRpcIds: [],
            latestIncomingUserText: nil, latestIncomingUserSeq: nil, previousMaxConfirmedSeq: 0
        )
        XCTAssertTrue(keep)
    }

    // M42：生成中发送模式与发件箱记录一致
    func testModeRecordedInOutboxMatchesDecider() {
        var lifecycle = MessageLifecycle()
        let mode = SendModeDecider.mode(isTurnRunning: true)
        lifecycle.begin(rpcId: "r", mode: mode)
        let outbox = Outbox(storage: InMemoryOutboxStorage())
        outbox.add(rpcId: "r", sessionId: "s", text: "hi", mode: mode, now: 0)
        XCTAssertEqual(outbox.allEntries.first?.mode, .steer)
        XCTAssertEqual(lifecycle.mode(for: "r"), .steer)
    }
}
