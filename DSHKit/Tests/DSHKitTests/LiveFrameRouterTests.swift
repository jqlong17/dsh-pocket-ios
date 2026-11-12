import XCTest
@testable import DSHKit

final class LiveFrameRouterTests: XCTestCase {
    func testSnapshot() {
        XCTAssertEqual(LiveFrameRouter.kind(of: ["type": "snapshot", "records": []]), .snapshot)
    }

    func testMessageEvent() {
        let value: [String: Any] = ["event": ["type": "user/message",
                                             "data": ["kind": "user", "message": ["sequence": 1]]]]
        XCTAssertEqual(LiveFrameRouter.kind(of: value), .message)
    }

    func testSteerInbox() {
        let value: [String: Any] = ["event": ["type": "agent/inbox/spliced",
                                             "data": ["inserted": [["source": ["rpcId": "R1"]]]]]]
        XCTAssertEqual(LiveFrameRouter.kind(of: value), .steerInbox)
        XCTAssertEqual(LiveFrameRouter.steerInboxRpcIds(from: value["event"] as! [String: Any]), ["r1"])
    }

    func testProcessEvent() {
        let value: [String: Any] = ["event": ["type": "tool/call", "data": ["name": "bash"]]]
        XCTAssertEqual(LiveFrameRouter.kind(of: value), .event)
    }

    func testUnknown() {
        XCTAssertEqual(LiveFrameRouter.kind(of: ["foo": 1]), .unknown)
    }

    func testSteerIdsIgnoreMalformed() {
        let event: [String: Any] = ["type": "agent/inbox/spliced", "data": ["inserted": "oops"]]
        XCTAssertTrue(LiveFrameRouter.steerInboxRpcIds(from: event).isEmpty)
    }

    func testDescribeUnknownFrame() {
        let value: [String: Any] = ["event": ["type": "weird", "data": ["source": ["kind": "system"]]]]
        let described = LiveFrameRouter.describe(value)
        XCTAssertEqual(described.type, "weird")
        XCTAssertEqual(described.sourceKind, "system")
    }
}
