import XCTest
@testable import DSHKit

final class SendLandedScanTests: XCTestCase {
    private func record(_ type: String, _ data: [String: Any]) -> [String: Any] {
        ["event": ["type": type, "data": data]]
    }

    func testLandsOnUserMessageWithRpcId() {
        let records = [record("user/message", ["source": ["rpcId": "abc-123"]])]
        XCTAssertTrue(SendLandedScan.landed(inRecords: records, requestId: "abc-123"))
    }

    func testLandsWhenSteeredIntoAgentInbox() {
        // 生成中 steer：消息进 inbox，不会立刻变成 user/message。
        let records = [record("agent/inbox/spliced",
                              ["inserted": [["source": ["rpcId": "abc-123"]]]])]
        XCTAssertTrue(SendLandedScan.landed(inRecords: records, requestId: "abc-123"))
    }

    func testIgnoresOtherRequests() {
        let records = [record("user/message", ["source": ["rpcId": "other"]])]
        XCTAssertFalse(SendLandedScan.landed(inRecords: records, requestId: "abc-123"))
    }

    func testIgnoresUnrelatedEvents() {
        let records = [record("assistant/message", ["text": "hi"]),
                       record("user/message", ["source": ["rpcId": "abc-123"]])]
        XCTAssertTrue(SendLandedScan.landed(inRecords: records, requestId: "abc-123"))
    }

    func testEmptyOrMalformedReturnsFalse() {
        XCTAssertFalse(SendLandedScan.landed(inRecords: [], requestId: "abc"))
        XCTAssertFalse(SendLandedScan.landed(inRecords: [["nope": 1]], requestId: "abc"))
    }
}
