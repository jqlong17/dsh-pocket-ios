import XCTest
@testable import DSHKit

final class PromptPayloadTests: XCTestCase {
    private let image = PromptPayload.Image(mediaType: "image/jpeg", base64: "AAAA", name: "a.jpg")

    func testTextOnlyProducesOneBlock() throws {
        let blocks = PromptPayload.content(text: "你好", images: [])
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0]["type"] as? String, "text")
        XCTAssertEqual(blocks[0]["text"] as? String, "你好")
    }

    func testEmptyTextProducesNoTextBlock() {
        // 空文本不能产生空 block：服务端会当成空消息。
        XCTAssertTrue(PromptPayload.content(text: "", images: []).isEmpty)
    }

    func testImageOnlyStillSendsImage() throws {
        let blocks = PromptPayload.content(text: "", images: [image])
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0]["type"] as? String, "image")
        XCTAssertEqual(blocks[0]["mediaType"] as? String, "image/jpeg")
        XCTAssertEqual(blocks[0]["data"] as? String, "AAAA")
        XCTAssertEqual(blocks[0]["name"] as? String, "a.jpg")
    }

    func testRequestCarriesAllFields() throws {
        let request = PromptPayload.request(requestId: "r1", sessionId: "s1", mode: .steer,
                                            text: "hi", images: [image], timeZone: "Asia/Shanghai")
        XCTAssertEqual(request["requestId"] as? String, "r1")
        XCTAssertEqual(request["sessionId"] as? String, "s1")
        XCTAssertEqual(request["mode"] as? String, "steer")
        XCTAssertEqual(request["clientTimeZone"] as? String, "Asia/Shanghai")
        let blocks = try XCTUnwrap(request["content"] as? [[String: Any]])
        XCTAssertEqual(blocks.count, 2, "文本 + 图片应有 2 个块")
    }

    func testQueueModeSerializes() {
        let request = PromptPayload.request(requestId: "r", sessionId: "s", mode: .queue,
                                            text: "x", images: [], timeZone: "UTC")
        XCTAssertEqual(request["mode"] as? String, "queue")
    }
}
