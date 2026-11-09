import XCTest
@testable import DSHKit

/// 回归：客户端大写 rpcId vs 服务端小写 rpcId 的大小写不一致 bug。
final class RPCIdTests: XCTestCase {
    // 1) 规范化
    func testNormalization() {
        XCTAssertEqual(RPCId.normalized("97D95E59-891A-4850-9F77-7AB972F33BD3"),
                       "97d95e59-891a-4850-9f77-7ab972f33bd3")
        XCTAssertEqual(RPCId.normalized("  AbC-123  "), "abc-123")
        XCTAssertNil(RPCId.normalized(nil))
        XCTAssertNil(RPCId.normalized("   "))
    }

    // 2) 匹配大小写无关
    func testMatchingIsCaseInsensitive() {
        XCTAssertTrue(RPCId.matches("ABC-1", "abc-1"))
        XCTAssertTrue(RPCId.matches("abc-1", "ABC-1"))
        XCTAssertFalse(RPCId.matches("abc-1", "abc-2"))
        XCTAssertFalse(RPCId.matches(nil, "abc-1"))
    }

    // 3) 解码事件时统一小写（服务端返回小写、客户端存大写也必须能匹配）
    func testDecodingNormalizesRpcId() {
        let event: [String: Any] = [
            "type": "user/message", "seq": 7,
            "data": [
                "content": [["type": "text", "text": "hi"]],
                "source": ["kind": "user", "rpcId": "97D95E59-891A-4850-9F77-7AB972F33BD3"]
            ]
        ]
        let message = DSHDecoding.message(fromEvent: event)
        XCTAssertEqual(message?.rpcId, "97d95e59-891a-4850-9f77-7ab972f33bd3")
    }

    // 4) PendingReconciler：大小写不同也算确认
    func testPendingReconcilerMatchesRpcIdCaseInsensitively() {
        let keep = PendingReconciler.shouldKeep(
            PendingCandidate(rpcId: "97D95E59-891A-4850-9F77-7AB972F33BD3", text: "x"),
            incomingRpcIds: ["97d95e59-891a-4850-9f77-7ab972f33bd3"],
            outboxRpcIds: ["97d95e59-891a-4850-9f77-7ab972f33bd3"],
            failedRpcIds: [],
            latestIncomingUserText: nil, latestIncomingUserSeq: nil, previousMaxConfirmedSeq: 0
        )
        XCTAssertFalse(keep, "大小写不同的 rpcId 也必须被视为已确认")

        let failed = PendingReconciler.shouldKeep(
            PendingCandidate(rpcId: "ABC-1", text: "x"),
            incomingRpcIds: [], outboxRpcIds: [], failedRpcIds: ["abc-1"],
            latestIncomingUserText: nil, latestIncomingUserSeq: nil, previousMaxConfirmedSeq: 0
        )
        XCTAssertTrue(failed)
    }

    // 5) Outbox 确认：大小写无关
    func testOutboxConfirmIsCaseInsensitive() {
        let outbox = Outbox(storage: InMemoryOutboxStorage())
        outbox.add(rpcId: "97D95E59-891A-4850-9F77-7AB972F33BD3",
                   sessionId: "s", text: "x", mode: .steer,
                   now: Date().timeIntervalSince1970)
        XCTAssertTrue(outbox.contains(rpcId: "97d95e59-891a-4850-9f77-7ab972f33bd3"))
        outbox.confirm(rpcIds: ["97d95e59-891A-4850-9F77-7AB972F33BD3"])
        XCTAssertFalse(outbox.contains(rpcId: "97D95E59-891A-4850-9F77-7AB972F33BD3"))
    }
}
