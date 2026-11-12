import XCTest
@testable import DSHKit

final class StreamItemsTests: XCTestCase {
    func testItemValueExtractedForMatchingFrame() {
        let frame: [String: Any] = [
            "streamId": "s1",
            "type": "item",
            "value": ["jobs": [["id": "a", "status": "running"]]]
        ]
        let value = StreamFrames.itemValue(frame, streamId: "s1")
        XCTAssertEqual((value?["jobs"] as? [[String: Any]])?.count, 1)
    }

    func testForeignStreamIdRejected() {
        let frame: [String: Any] = ["streamId": "other", "type": "item", "value": [:]]
        XCTAssertNil(StreamFrames.itemValue(frame, streamId: "s1"))
    }

    func testNonItemFrameRejected() {
        let frame: [String: Any] = ["streamId": "s1", "type": "opened", "value": [:]]
        XCTAssertNil(StreamFrames.itemValue(frame, streamId: "s1"))
    }

    func testMissingValueRejected() {
        let frame: [String: Any] = ["streamId": "s1", "type": "item"]
        XCTAssertNil(StreamFrames.itemValue(frame, streamId: "s1"))
    }

    func testValueOfWrongTypeRejected() {
        let frame: [String: Any] = ["streamId": "s1", "type": "item", "value": "oops"]
        XCTAssertNil(StreamFrames.itemValue(frame, streamId: "s1"))
    }
}

final class StepEventSequenceTests: XCTestCase {
    func testSequenceForEachCase() {
        XCTAssertEqual(DSHStepEvent.toolCall(seq: 11, turn: 1, callId: "c", name: "bash",
                                             detail: "", arguments: "{}").sequence, 11)
        XCTAssertEqual(DSHStepEvent.toolResult(seq: 12, turn: 1, callId: "c", text: "",
                                              isError: false, images: []).sequence, 12)
        XCTAssertEqual(DSHStepEvent.turnStart(seq: 13, turn: 1).sequence, 13)
        XCTAssertEqual(DSHStepEvent.turnEnd(seq: 14, turn: 1, failure: nil).sequence, 14)
    }
}
