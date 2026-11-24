import XCTest
@testable import DSHKit

final class QuestionReplyDecodingTests: XCTestCase {
    private func replyEvent(source: [String: Any], seq: Int = 12) -> [String: Any] {
        [
            "type": "user/message",
            "seq": seq,
            "data": [
                "message": [
                    "content": [["type": "text", "text": #"{"answers":[{"id":"model","selected":["gemma4"]}]}"#]],
                    "source": source,
                ]
            ]
        ]
    }

    func testReplyCallIdFromMessageSource() {
        let event = replyEvent(source: ["kind": "user-question-reply", "callId": "call-1"])
        XCTAssertEqual(DSHDecoding.questionReplyCallId(fromEvent: event), "call-1")
    }

    func testReplyCallIdFromDataLevelSource() {
        let event: [String: Any] = [
            "type": "user/message",
            "seq": 13,
            "data": [
                "source": ["kind": "user-question-reply", "callId": "call-2"],
                "message": ["content": [["type": "text", "text": "{}"]]],
            ]
        ]
        XCTAssertEqual(DSHDecoding.questionReplyCallId(fromEvent: event), "call-2")
        XCTAssertEqual(DSHDecoding.questionReplyCallId(fromRecord: ["event": event]), "call-2")
    }

    func testNormalUserMessageIsNotAQuestionReply() {
        let event = replyEvent(source: ["kind": "user", "rpcId": "r-1"])
        XCTAssertNil(DSHDecoding.questionReplyCallId(fromEvent: event))

        let assistant: [String: Any] = ["type": "assistant/message", "seq": 2, "data": [:]]
        XCTAssertNil(DSHDecoding.questionReplyCallId(fromEvent: assistant))
    }

    func testReplyWithoutCallIdIsRejected() {
        let event = replyEvent(source: ["kind": "user-question-reply"])
        XCTAssertNil(DSHDecoding.questionReplyCallId(fromEvent: event))
    }

    func testReplyMessageDecodesWithSourceFields() {
        let event = replyEvent(source: ["kind": "user-question-reply", "callId": "call-9"])
        guard let message = DSHDecoding.message(fromEvent: event) else {
            return XCTFail("问答回复应解码出 DSHMessage")
        }
        XCTAssertEqual(message.sourceKind, "user-question-reply")
        XCTAssertEqual(message.sourceCallId, "call-9")
        XCTAssertEqual(message.isUser, true)
    }

    func testInjectedContextStillFiltered() {
        let event = replyEvent(source: ["kind": "runtime-context"])
        XCTAssertNil(DSHDecoding.message(fromEvent: event))
    }

    func testPendingResultDetection() {
        XCTAssertTrue(QuestionAnswerReplay.isPendingResult(#"{"pending":true}"#))
        XCTAssertTrue(QuestionAnswerReplay.isPendingResult("  {\"pending\": true}  "))
        XCTAssertFalse(QuestionAnswerReplay.isPendingResult(#"{"answers":[{"id":"a","selected":["x"]}]}"#))
        XCTAssertFalse(QuestionAnswerReplay.isPendingResult(#"{"pending":false}"#))
        XCTAssertFalse(QuestionAnswerReplay.isPendingResult("已中止：用户未回答"))
        XCTAssertFalse(QuestionAnswerReplay.isPendingResult(""))
    }
}
