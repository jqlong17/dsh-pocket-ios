import XCTest
@testable import DSHKit

final class RPCTests: XCTestCase {
    // P03
    func testRPCEnvelopeEncoding() throws {
        let rpcId = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let request = RPCRequest(method: "session/list", rpcId: rpcId, args: ["_request": ["excludeArchived": true]])
        let data = try request.encoded()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["type"] as? String, "client-request")
        XCTAssertEqual(json["rpcId"] as? String, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(json["method"] as? String, "session/list")
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        let args = try XCTUnwrap(payload["args"] as? [String: Any])
        XCTAssertNotNil(args["_request"])
    }

    // P03 变体：解包 result.value
    func testRPCValueUnwrap() throws {
        let body = Data(#"{"result":{"value":{"items":[]}}}"#.utf8)
        let value = try RPCRequest.value(from: body)
        XCTAssertNotNil(value["items"])
    }

    // P04
    func testStreamOpenFrameEncoding() throws {
        let frame = StreamFrames.openFrame(streamId: "stream-1", sessionId: "session-1", maxMessages: 30)
        XCTAssertEqual(frame["type"] as? String, "open")
        XCTAssertEqual(frame["streamId"] as? String, "stream-1")
        XCTAssertEqual(frame["endpoint"] as? String, "session/follow")

        let payload = try XCTUnwrap(frame["payload"] as? [String: Any])
        let args = try XCTUnwrap(payload["args"] as? [String: Any])
        let request = try XCTUnwrap(args["request"] as? [String: Any])
        XCTAssertEqual(request["maxMessages"] as? Int, 30)
        let address = try XCTUnwrap(request["address"] as? [String: Any])
        XCTAssertEqual(address["kind"] as? String, "session")
        XCTAssertEqual(address["sessionId"] as? String, "session-1")
    }

    // P05
    func testItemFrameMatching() {
        let good: [String: Any] = ["type": "item", "streamId": "stream-1", "value": [:]]
        let wrongStream: [String: Any] = ["type": "item", "streamId": "stream-2", "value": [:]]
        let wrongType: [String: Any] = ["type": "open", "streamId": "stream-1"]

        XCTAssertTrue(StreamFrames.isItemFrame(good, streamId: "stream-1"))
        XCTAssertFalse(StreamFrames.isItemFrame(wrongStream, streamId: "stream-1"))
        XCTAssertFalse(StreamFrames.isItemFrame(wrongType, streamId: "stream-1"))
    }
}
