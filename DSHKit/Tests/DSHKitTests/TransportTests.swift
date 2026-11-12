import XCTest
@testable import DSHKit

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: DSHError.invalidPayload)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class TransportTests: XCTestCase {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testURLSessionHTTPTransportReturnsData() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("ok".utf8))
        }
        let transport = DSHURLSessionHTTPTransport(session: makeSession())
        var request = URLRequest(url: URL(string: "http://localhost/api/x")!)
        request.httpMethod = "POST"
        let (data, response) = try await transport.data(for: request)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), "ok")
    }

    /// 传输层错误必须**保留 URLError**：错误码是「要不要重试 / 算不算断网」的唯一依据。
    /// 曾经包成 DSHError.transport，导致飞行模式下发消息被判为「发送失败」而不是断网暂存，
    /// 联网后也不会自动补发（2026-11-12 用户实测）。
    func testURLSessionHTTPTransportPreservesURLError() async {
        MockURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        let transport = DSHURLSessionHTTPTransport(session: makeSession())
        do {
            _ = try await transport.data(for: URLRequest(url: URL(string: "http://localhost/api/x")!))
            XCTFail("expected transport error")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cannotConnectToHost)
            XCTAssertTrue(DSHNetworkErrorPolicy.isTransient(error), "断网必须可被识别为瞬时故障")
        } catch {
            XCTFail("应保留 URLError，实际: \(error)")
        }
    }
}
