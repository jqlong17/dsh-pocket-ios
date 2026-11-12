import XCTest
@testable import DSHKit

final class PendingQuestionDecodingTests: XCTestCase {
    func testDecodesQuestionsAndOptions() throws {
        let json = """
        {"questions":[{"id":"q1","header":"确认","question":"要发布吗？","detail":"影响线上",
        "options":[{"label":"发布","description":"立即"},{"label":"取消"}],"multiSelect":true}]}
        """
        let payload = try XCTUnwrap(PendingQuestionPayload.decode(callId: "call-1", arguments: json))
        XCTAssertEqual(payload.callId, "call-1")
        XCTAssertEqual(payload.questions.count, 1)
        let item = try XCTUnwrap(payload.questions.first)
        XCTAssertEqual(item.id, "q1")
        XCTAssertEqual(item.header, "确认")
        XCTAssertEqual(item.question, "要发布吗？")
        XCTAssertEqual(item.detail, "影响线上")
        XCTAssertTrue(item.multiSelect)
        XCTAssertEqual(item.options.map(\.label), ["发布", "取消"])
        XCTAssertEqual(item.options.first?.description, "立即")
    }

    func testDefaultsMultiSelectToFalse() throws {
        let json = #"{"questions":[{"id":"q","question":"继续？"}]}"#
        let payload = try XCTUnwrap(PendingQuestionPayload.decode(callId: "c", arguments: json))
        XCTAssertFalse(try XCTUnwrap(payload.questions.first).multiSelect)
        XCTAssertTrue(try XCTUnwrap(payload.questions.first).options.isEmpty)
    }

    func testRejectsMalformedInput() {
        XCTAssertNil(PendingQuestionPayload.decode(callId: "c", arguments: "not json"))
        XCTAssertNil(PendingQuestionPayload.decode(callId: "c", arguments: #"{"questions":[]}"#))
        XCTAssertNil(PendingQuestionPayload.decode(callId: "c", arguments: #"{"questions":[{"id":"q"}]}"#))
    }
}
