import XCTest
@testable import DSHKit

final class DecodingExtraTests: XCTestCase {
    func testStreamStartEndAndOther() throws {
        let start: [String: Any] = [
            "type": "assistant-stream",
            "frame": ["type": "start", "attemptId": "a1", "turn": 3, "step": 2]
        ]
        guard case .start(let attemptId, let turn, let step)? = DSHDecoding.streamFrame(fromJSON: start) else {
            return XCTFail("expected start")
        }
        XCTAssertEqual(attemptId, "a1")
        XCTAssertEqual(turn, 3)
        XCTAssertEqual(step, 2)

        let end: [String: Any] = [
            "type": "assistant-stream",
            "frame": ["type": "end", "attemptId": "a1", "outcome": ["kind": "committed"]]
        ]
        guard case .end(let endId, let outcome)? = DSHDecoding.streamFrame(fromJSON: end) else {
            return XCTFail("expected end")
        }
        XCTAssertEqual(endId, "a1")
        XCTAssertEqual(outcome, "committed")

        let reasoning: [String: Any] = [
            "type": "assistant-stream",
            "frame": ["type": "chunk", "attemptId": "a1", "index": 0,
                      "chunk": ["type": "reasoning-delta", "text": "thinking"]]
        ]
        XCTAssertEqual(DSHDecoding.streamFrame(fromJSON: reasoning), .other)
        XCTAssertNil(DSHDecoding.streamFrame(fromJSON: ["type": "assistant-stream"]))
        XCTAssertNil(DSHDecoding.streamFrame(fromJSON: ["type": "event"]))
    }

    func testToolResultErrorFlag() {
        let event: [String: Any] = [
            "type": "tool/result",
            "seq": 11,
            "data": [
                "turn": 2,
                "toolCallId": "call-x",
                "isError": true,
                "message": ["content": [["type": "text", "text": "boom"]]]
            ]
        ]
        guard case .toolResult(let seq, let turn, let callId, let text, let isError, _)? = DSHDecoding.stepEvent(fromEvent: event) else {
            return XCTFail("expected toolResult")
        }
        XCTAssertEqual(seq, 11)
        XCTAssertEqual(turn, 2)
        XCTAssertEqual(callId, "call-x")
        XCTAssertEqual(text, "boom")
        XCTAssertTrue(isError)
    }


    // 回归：tool/result 里的截图（type=image + attachment）必须被解码出来
    func testToolResultImagesDecoded() {
        let event: [String: Any] = [
            "type": "tool/result", "seq": 2783,
            "data": [
                "turn": 28, "toolCallId": "call-x",
                "message": ["role": "tool", "content": [
                    ["type": "text", "text": "screenshot saved"],
                    ["type": "image", "attachment": [
                        "attachmentId": "sha256:1b65b320",
                        "mediaType": "image/png", "bytes": 343367,
                        "width": 2160, "height": 1350, "name": "shot.png"
                    ]]
                ]]
            ]
        ]
        guard case .toolResult(_, _, _, _, _, let images)? = DSHDecoding.stepEvent(fromEvent: event) else {
            return XCTFail("expected toolResult")
        }
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.attachmentId, "sha256:1b65b320")
        XCTAssertEqual(images.first?.mediaType, "image/png")
        XCTAssertEqual(images.first?.width, 2160)
        XCTAssertEqual(images.first?.name, "shot.png")
    }

    func testArgumentDetailFallsBackToPathAndRawArguments() {
        XCTAssertEqual(DSHDecoding.argumentDetail(name: "read", arguments: #"{"path":"/tmp/a.ts"}"#), "/tmp/a.ts")
        XCTAssertEqual(DSHDecoding.argumentDetail(name: "web_search", arguments: #"{"queries":["a","b"]}"#), "a / b")
        XCTAssertEqual(DSHDecoding.argumentDetail(name: "read", arguments: "not-json"), "not-json")
        XCTAssertEqual(DSHDecoding.argumentDetail(name: "custom", arguments: #"{"other":1}"#), "custom")
        XCTAssertEqual(DSHDecoding.argumentDetail(name: "bash", arguments: #"{"cmd":"echo hi"}"#), "echo hi")
    }

    func testMessageWithoutContentReturnsNil() {
        let empty: [String: Any] = [
            "type": "assistant/message", "seq": 1,
            "data": ["message": ["content": []]]
        ]
        XCTAssertNil(DSHDecoding.message(fromEvent: empty))
    }

    func testSessionMissingIDReturnsNil() {
        XCTAssertNil(DSHDecoding.session(fromJSON: ["updatedAt": 1]))
    }

    func testSessionWithWhitespaceTitleIsInvisible() {
        let session = DSHSession(sessionId: "s", updatedAt: 0, running: false, blank: false, title: "   ")
        XCTAssertFalse(session.isVisibleInList)
        XCTAssertNil(DSHDecoding.session(fromJSON: ["sessionId": "s", "projections": ["values": ["title": "   "]]])?.title?.isEmpty == false ? nil : session)
    }

    func testRPCValueRejectsInvalidJSON() {
        XCTAssertThrowsError(try RPCRequest.value(from: Data("not-json".utf8))) { error in
            XCTAssertEqual(error as? DSHError, .invalidPayload)
        }
        XCTAssertThrowsError(try RPCRequest.value(from: Data(#"{"result":{}}"#.utf8)))
    }
}
