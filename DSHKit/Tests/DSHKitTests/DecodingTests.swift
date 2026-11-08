import XCTest
@testable import DSHKit

final class DecodingTests: XCTestCase {
    private func pageRecords() throws -> [DSHRecord] {
        let json = try fixtureJSON("session_page")
        return DSHDecoding.page(fromValue: json).records
    }

    // P20
    func testDecodeUserMessageWithRpcId() throws {
        let userEvents = try pageRecords().compactMap { record -> DSHMessage? in
            if case .message(let message) = record, message.isUser { return message }
            return nil
        }
        let first = try XCTUnwrap(userEvents.first)
        XCTAssertEqual(first.text, "你好")
        XCTAssertEqual(first.rpcId, "RPC-1")
        XCTAssertEqual(first.sequence, 2)
    }

    // P21
    func testInjectedContextIsNotAUserMessage() throws {
        let texts = try pageRecords().compactMap { record -> String? in
            if case .message(let message) = record, message.isUser { return message.text }
            return nil
        }
        XCTAssertFalse(texts.contains("runtime context injected"))
    }

    // P22
    func testDecodeAssistantMessage() throws {
        let assistant = try pageRecords().compactMap { record -> DSHMessage? in
            if case .message(let message) = record, !message.isUser { return message }
            return nil
        }
        XCTAssertEqual(assistant.first?.text, "你好！")
        XCTAssertEqual(assistant.first?.kind, "assistant/message")
    }

    // P23
    func testDecodeToolCallAndResult() throws {
        let steps = try pageRecords().compactMap { record -> DSHStepEvent? in
            if case .step(let step) = record { return step }
            return nil
        }
        let toolCalls = steps.filter { if case .toolCall = $0 { return true }; return false }
        guard case .toolCall(_, _, let callId, let name, let detail)? = toolCalls.first else {
            return XCTFail("tool/call missing")
        }
        XCTAssertEqual(callId, "call-1")
        XCTAssertEqual(name, "bash")
        XCTAssertEqual(detail, "ls -la")

        let toolResults = steps.filter { if case .toolResult = $0 { return true }; return false }
        guard case .toolResult(_, _, let resultCallId, let text, let isError)? = toolResults.first else {
            return XCTFail("tool/result missing")
        }
        XCTAssertEqual(resultCallId, "call-1")
        XCTAssertEqual(text, "total 0")
        XCTAssertFalse(isError)
    }

    // P24
    func testDecodeTurnBoundaries() throws {
        let steps = try pageRecords().compactMap { record -> DSHStepEvent? in
            if case .step(let step) = record { return step }
            return nil
        }
        XCTAssertTrue(steps.contains { if case .turnStart(seq: 4, turn: 1) = $0 { return true }; return false })
        XCTAssertTrue(steps.contains { if case .turnEnd(seq: 8, turn: 1) = $0 { return true }; return false })
    }

    // P25
    func testDecodeAssistantStreamTextDelta() throws {
        let json = try fixtureJSON("stream_frame")
        let frame = try XCTUnwrap(DSHDecoding.streamFrame(fromJSON: json))
        guard case .textDelta(let attemptId, let index, let text) = frame else {
            return XCTFail("expected textDelta")
        }
        XCTAssertEqual(attemptId, "attempt-1")
        XCTAssertEqual(index, 3)
        XCTAssertEqual(text, "你好")
    }

    // P26
    func testDecodeImageAttachment() throws {
        let messages = try pageRecords().compactMap { record -> DSHMessage? in
            if case .message(let message) = record { return message }
            return nil
        }
        let withImage = try XCTUnwrap(messages.first { !$0.images.isEmpty })
        XCTAssertEqual(withImage.text, "看图")
        XCTAssertEqual(withImage.images.first?.attachmentId, "att-1")
        XCTAssertEqual(withImage.images.first?.mediaType, "image/jpeg")
        XCTAssertEqual(withImage.images.first?.width, 640)
    }

    // P27
    func testUnknownEventIsIgnored() throws {
        let event: [String: Any] = ["type": "unknown/event", "seq": 99, "data": ["foo": "bar"]]
        XCTAssertNil(DSHDecoding.message(fromEvent: event))
        XCTAssertNil(DSHDecoding.stepEvent(fromEvent: event))
    }

    // 附加：标题事件解码
    func testDecodeSessionTitleRecord() throws {
        let titles = try pageRecords().compactMap { record -> String? in
            if case .title(_, let title) = record { return title }
            return nil
        }
        XCTAssertEqual(titles.first, "问候")
    }
}
