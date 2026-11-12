import Foundation

/// 协议客户端门面：登录 + RPC + 会话列表/历史（模块 01 提供基础能力，模块 02 在其上做同步）。
public final class DSHClient: @unchecked Sendable {
    public let baseURL: URL
    private let http: DSHHTTPTransport
    private let webSocket: DSHWebSocketTransport

    /// 重试之间的等待。测试注入空实现即可秒过；生产用 `RPCRetryPolicy.backoff`。
    private let retrySleep: @Sendable (Int) async -> Void

    public init(baseURL: URL,
                http: DSHHTTPTransport = DSHURLSessionHTTPTransport(),
                webSocket: DSHWebSocketTransport = DSHURLSessionWebSocketTransport(),
                retrySleep: (@Sendable (Int) async -> Void)? = nil) {
        self.baseURL = baseURL
        self.http = http
        self.webSocket = webSocket
        self.retrySleep = retrySleep ?? { attempt in
            try? await Task.sleep(for: RPCRetryPolicy.backoff(attempt: attempt))
        }
    }

    public func webSocketURL(path: String = StreamFrames.remoteMuxPath) -> URL? {
        DSHURL.webSocketURL(from: baseURL, path: path)
    }

    public func connectWebSocket() async throws -> DSHWebSocketConnection {
        guard let url = webSocketURL() else { throw DSHError.invalidAddress }
        return try await webSocket.connect(url: url)
    }

    /// 登录：POST /pocket-login（表单 token=PIN），根据重定向/cookie 判定结果。
    public func login(pin: String) async throws -> LoginOutcome {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw DSHError.invalidAddress
        }
        components.path = "/pocket-login"
        guard let url = components.url else { throw DSHError.invalidAddress }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "token=\(pin.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? pin)".data(using: .utf8)

        let (_, http) = try await http.data(for: request)
        let redirected = http.statusCode == 302 || http.statusCode == 303
        let cookies = http.value(forHTTPHeaderField: "Set-Cookie") ?? ""
        let hasPocketCookie = cookies.contains("dsh_pocket_token")
        return LoginClassifier.outcome(statusCode: http.statusCode,
                                       redirected: redirected,
                                       hasPocketCookie: hasPocketCookie)
    }

    /// 发送一个 RPC 并返回 `result.value`。
    ///
    /// - Parameter timeout: 单次请求超时，默认 20 秒（沿用 App 层旧值，避免行为漂移）。
    public func rpc(method: String, args: [String: Any],
                    timeout: TimeInterval = 20) async throws -> [String: Any] {
        try await rpc(RPCRequest(method: method, args: args), timeout: timeout)
    }

    /// 带重试的 RPC：**同一个 rpcId 贯穿所有尝试**，服务端按 rpcId 去重，不会重复执行。
    ///
    /// 只对瞬时错误重试（见 `RPCRetryPolicy`）；401/400 这类业务错误第一次就抛。
    public func rpcWithRetry(method: String, args: [String: Any],
                             attempts: Int = 3,
                             timeout: TimeInterval = 20) async throws -> [String: Any] {
        let request = RPCRequest(method: method, args: args)
        var lastError: Error = DSHError.invalidPayload
        for attempt in 0..<max(attempts, 1) {
            do {
                return try await rpc(request, timeout: timeout)
            } catch {
                lastError = error
                guard RPCRetryPolicy.shouldRetry(error, attempt: attempt, maxAttempts: attempts) else {
                    throw error
                }
                await retrySleep(attempt)
            }
        }
        throw lastError
    }

    /// 单次发送。抽出私有入口是为了让重试能复用同一个 `RPCRequest`（即同一个 rpcId）。
    private func rpc(_ request: RPCRequest, timeout: TimeInterval) async throws -> [String: Any] {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/\(request.method)"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try request.encoded()

        let (data, http) = try await self.http.data(for: urlRequest)
        if let error = DSHError.from(status: http.statusCode,
                                     message: String(data: data, encoding: .utf8)) {
            throw error
        }
        return try RPCRequest.value(from: data)
    }

    public func sessions(excludeArchived: Bool = true) async throws -> [DSHSession] {
        let value = try await rpc(method: "session/list", args: ["_request": ["excludeArchived": excludeArchived]])
        let items = value["items"] as? [[String: Any]] ?? []
        return items.compactMap(DSHDecoding.session(fromJSON:))
    }

    public func page(sessionId: String, maxMessages: Int,
                     beforeSeq: Int? = nil, throughSeq: Int? = nil) async throws -> DSHSessionPage {
        var request: [String: Any] = [
            "address": ["kind": "session", "sessionId": sessionId],
            "maxMessages": maxMessages
        ]
        // 分页游标：beforeSeq 是"更早一页"的排他上界（DSH SessionPageRequest）。
        if let beforeSeq { request["beforeSeq"] = beforeSeq }
        if let throughSeq { request["throughSeq"] = throughSeq }
        let value = try await rpc(method: "session/page", args: ["request": request])
        return DSHDecoding.page(fromValue: value)
    }
}
