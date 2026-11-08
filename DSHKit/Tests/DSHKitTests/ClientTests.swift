import XCTest
@testable import DSHKit

final class ClientTests: XCTestCase {
    private func client(transport: MockHTTPTransport, ws: MockWebSocketTransport = MockWebSocketTransport()) throws -> DSHClient {
        let base = try XCTUnwrap(DSHURL.normalizedBase("http://192.168.1.10:3081"))
        return DSHClient(baseURL: base, http: transport, webSocket: ws)
    }

    func testWebSocketURLUsesClientBase() throws {
        let client = try client(transport: MockHTTPTransport { _ in .init(status: 200, body: Data(), headers: [:]) })
        XCTAssertEqual(client.webSocketURL()?.absoluteString, "ws://192.168.1.10:3081/api/remote.mux")
    }

    func testConnectWebSocketUsesTransport() async throws {
        let ws = MockWebSocketTransport()
        let client = try client(transport: MockHTTPTransport { _ in .init(status: 200, body: Data(), headers: [:]) }, ws: ws)
        _ = try await client.connectWebSocket()
        XCTAssertEqual(ws.connectedURL?.absoluteString, "ws://192.168.1.10:3081/api/remote.mux")
    }

    func testLoginSuccessThroughClient() async throws {
        let transport = MockHTTPTransport { _ in
            .init(status: 302, body: Data(), headers: ["Set-Cookie": "dsh_pocket_token=abc; Path=/"])
        }
        let outcome = try await client(transport: transport).login(pin: "12345678")
        XCTAssertEqual(outcome, .success)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/pocket-login")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("token=12345678"))
    }

    func testLoginWrongPINThroughClient() async throws {
        let transport = MockHTTPTransport { _ in .init(status: 200, body: Data("<html>login</html>".utf8), headers: [:]) }
        let outcome = try await client(transport: transport).login(pin: "bad")
        XCTAssertEqual(outcome, .invalidPIN)
    }

    func testRPCUnauthorizedThrows() async throws {
        let transport = MockHTTPTransport { _ in .init(status: 401, body: Data(), headers: [:]) }
        do {
            _ = try await client(transport: transport).rpc(method: "session/list", args: [:])
            XCTFail("expected unauthorized")
        } catch let error as DSHError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testRPCValueErrorIsThrown() async throws {
        let body = Data(#"{"error":{"message":"boom","status":500}}"#.utf8)
        let transport = MockHTTPTransport { _ in .init(status: 200, body: body, headers: [:]) }
        do {
            _ = try await client(transport: transport).rpc(method: "session/list", args: [:])
            XCTFail("expected server error")
        } catch let error as DSHError {
            XCTAssertEqual(error, .server(status: 500, message: "boom"))
        }
    }

    func testSessionsDecodingThroughClient() async throws {
        let items = try fixtureData("session_list")
        let payload = try JSONSerialization.data(withJSONObject: ["result": ["value": ["items": try fixtureJSON("session_list")["items"]!]]])
        let transport = MockHTTPTransport { _ in .init(status: 200, body: payload, headers: [:]) }
        let sessions = try await client(transport: transport).sessions()
        XCTAssertEqual(sessions.count, 4)
        XCTAssertEqual(sessions.first?.sessionId, "session-normal-1")
        _ = items
    }

    func testPageDecodingThroughClient() async throws {
        let value: [String: Any] = [
            "result": ["value": try fixtureJSON("session_page")]
        ]
        let payload = try JSONSerialization.data(withJSONObject: value)
        let transport = MockHTTPTransport { _ in .init(status: 200, body: payload, headers: [:]) }
        let page = try await client(transport: transport).page(sessionId: "session-normal-1", maxMessages: 30)
        XCTAssertEqual(page.records.count, 10)
        XCTAssertTrue(page.hasMore)
    }

    func testInvalidAddressThrows() throws {
        let client = DSHClient(baseURL: URL(string: "http://")!)
        XCTAssertNil(client.webSocketURL())
    }
}
