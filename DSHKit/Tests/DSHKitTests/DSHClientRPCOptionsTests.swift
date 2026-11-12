import XCTest
@testable import DSHKit

/// DSHClient 的 RPC 选项：超时、重试、以及 `result.ok == false` 这种失败形状。
///
/// 为什么这些要测：
/// - 超时以前是「App 设 20 秒、DSHKit 不设」，两套实现必然不一致；
/// - `result.ok == false` 只有 App 那份实现认得，收口后 DSHKit 必须也认，否则服务端业务失败会被当成成功；
/// - 重试必须是同一个 rpcId，否则服务端去重失效，用户会看到重复消息。
final class DSHClientRPCOptionsTests: XCTestCase {
    private func okBody(_ value: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["result": ["value": value]])) ?? Data()
    }

    private func client(_ transport: DSHHTTPTransport) -> DSHClient {
        DSHClient(baseURL: URL(string: "http://127.0.0.1:3081")!,
                  http: transport,
                  webSocket: MockWebSocketTransport(),
                  retrySleep: { _ in })
    }

    // MARK: 超时

    func testDefaultTimeoutIsTwentySeconds() async throws {
        let transport = FlakyHTTPTransport { _ in .success((200, self.okBody(["ok": true]))) }
        _ = try await client(transport).rpc(method: "session/list", args: [:])
        XCTAssertEqual(transport.requests.last?.timeoutInterval, 20)
    }

    func testExplicitTimeoutIsApplied() async throws {
        let transport = FlakyHTTPTransport { _ in .success((200, self.okBody(["ok": true]))) }
        _ = try await client(transport).rpc(method: "session/list", args: [:], timeout: 5)
        XCTAssertEqual(transport.requests.last?.timeoutInterval, 5)
    }

    // MARK: result.ok == false

    func testResultOkFalseThrowsServerErrorWithMessage() async {
        let body = (try? JSONSerialization.data(withJSONObject: [
            "result": ["ok": false, "error": ["message": "会话不存在"]]
        ])) ?? Data()
        let transport = FlakyHTTPTransport { _ in .success((200, body)) }
        do {
            _ = try await client(transport).rpc(method: "session/page", args: [:])
            XCTFail("result.ok == false 应当抛错")
        } catch let error as DSHError {
            guard case .server(_, let message) = error else {
                return XCTFail("期望 .server，实际 \(error)")
            }
            XCTAssertEqual(message, "会话不存在")
        } catch {
            XCTFail("期望 DSHError，实际 \(error)")
        }
    }

    // MARK: 重试

    func testRetrySucceedsAfterTransientFailures() async throws {
        let transport = FlakyHTTPTransport { attempt in
            attempt < 3
                ? .failure(URLError(.timedOut))
                : .success((200, self.okBody(["ok": true])))
        }
        let value = try await client(transport)
            .rpcWithRetry(method: "session/prompt", args: ["request": ["requestId": "r1"]])
        XCTAssertEqual(value["ok"] as? Bool, true)
        XCTAssertEqual(transport.attempts, 3)
    }

    func testRetryKeepsSameRpcIdAcrossAttempts() async throws {
        let transport = FlakyHTTPTransport { attempt in
            attempt < 2 ? .failure(URLError(.networkConnectionLost)) : .success((200, self.okBody(["ok": true])))
        }
        _ = try await client(transport).rpcWithRetry(method: "session/prompt", args: [:])
        let ids = transport.requests.compactMap { request -> String? in
            guard let body = request.httpBody,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
            return json["rpcId"] as? String
        }
        XCTAssertEqual(Set(ids).count, 1, "重试必须复用同一个 rpcId，否则服务端去重失效")
    }

    func testRetryDoesNotRetryPermanentError() async {
        let transport = FlakyHTTPTransport { _ in .success((401, Data())) }
        do {
            _ = try await client(transport).rpcWithRetry(method: "session/prompt", args: [:])
            XCTFail("401 不应重试")
        } catch {
            XCTAssertEqual(transport.attempts, 1)
        }
    }

    func testRetryExhaustsAttemptsAndThrowsLastError() async {
        let transport = FlakyHTTPTransport { _ in .failure(URLError(.timedOut)) }
        do {
            _ = try await client(transport).rpcWithRetry(method: "session/prompt", args: [:], attempts: 3)
            XCTFail("应当抛错")
        } catch {
            XCTAssertEqual(transport.attempts, 3)
        }
    }

    // MARK: 请求形状（收口后仍打到 api/<method> 且是 POST）

    func testRequestShapeStaysSame() async throws {
        let transport = FlakyHTTPTransport { _ in .success((200, self.okBody(["ok": true]))) }
        _ = try await client(transport).rpc(method: "session/list", args: ["_request": ["excludeArchived": true]])
        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.url?.path.hasSuffix("/api/session/list") ?? false, "实际: \(request.url?.path ?? "nil")")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "client-request")
        XCTAssertEqual(json["method"] as? String, "session/list")
        XCTAssertNotNil(json["rpcId"])
    }
}
