import Foundation
@testable import DSHKit

/// 测试用 HTTP 传输：返回预置响应。
final class MockHTTPTransport: DSHHTTPTransport, @unchecked Sendable {
    struct Response {
        let status: Int
        let body: Data
        let headers: [String: String]
    }

    private let handler: (URLRequest) -> Response
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping (URLRequest) -> Response) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = handler(request)
        let http = HTTPURLResponse(url: request.url ?? URL(string: "http://localhost")!,
                                   statusCode: response.status,
                                   httpVersion: "HTTP/1.1",
                                   headerFields: response.headers)!
        return (response.body, http)
    }
}

final class MockWebSocketConnection: DSHWebSocketConnection, @unchecked Sendable {
    private(set) var sent: [String] = []
    private let frames: [Data]
    private var index = 0

    init(frames: [Data] = []) { self.frames = frames }

    func send(text: String) async throws { sent.append(text) }

    func receive() async throws -> Data {
        guard index < frames.count else { throw DSHError.invalidPayload }
        defer { index += 1 }
        return frames[index]
    }

    func cancel() {}
}

final class MockWebSocketTransport: DSHWebSocketTransport, @unchecked Sendable {
    let connection: MockWebSocketConnection
    private(set) var connectedURL: URL?

    init(connection: MockWebSocketConnection = MockWebSocketConnection()) {
        self.connection = connection
    }

    func connect(url: URL) async throws -> DSHWebSocketConnection {
        connectedURL = url
        return connection
    }
}

func fixtureData(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        ?? Bundle.module.url(forResource: name, withExtension: "json") else {
        throw DSHError.invalidPayload
    }
    return try Data(contentsOf: url)
}

func fixtureJSON(_ name: String) throws -> [String: Any] {
    let data = try fixtureData(name)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw DSHError.invalidPayload
    }
    return object
}
