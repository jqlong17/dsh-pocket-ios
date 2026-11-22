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

    /// 回传 `$events` 请求的处理结果。
    ///
    /// 路径是 `/api/$events/result`（浏览器端同样是 `rpc.call('/api', '$events/result', ...)`）。
    /// 不能用 `appendingPathComponent`——它会把 `$` 转义掉。
    public func remoteEventResult(_ body: [String: Any],
                                  timeout: TimeInterval = 20) async throws {
        guard let url = URL(string: baseURL.absoluteString
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .appending("/api/\(RemoteEventProtocol.resultEndpoint)")) else {
            throw DSHError.invalidPayload
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try RPCRequest(method: RemoteEventProtocol.resultEndpoint,
                                             args: body).encoded()
        let (data, http) = try await self.http.data(for: urlRequest)
        if let error = DSHError.from(status: http.statusCode,
                                     message: String(data: data, encoding: .utf8)) {
            throw error
        }
        try RPCRequest.ok(from: data)
    }

    /// 命令式 RPC：只确认服务端接受了，**不解析返回体**。
    ///
    /// 用于 `userQuestions/answer` 这类「做完就行」的接口——它们的 `value`
    /// 可能是 null 或非字典，用 `rpc()` 会误报「服务器响应格式无效」。
    /// 同 `rpcVoid`，但返回原始响应体（诊断用：命令式接口出错时看不清服务端到底回了什么）。
    public func rpcVoidRaw(method: String, args: [String: Any],
                           timeout: TimeInterval = 20) async throws -> String {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/\(method)"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try RPCRequest(method: method, args: args).encoded()
        let (data, http) = try await self.http.data(for: urlRequest)
        let text = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count)B>"
        if let error = DSHError.from(status: http.statusCode, message: text) {
            throw error
        }
        try RPCRequest.ok(from: data)
        return text
    }

    public func rpcVoid(method: String, args: [String: Any],
                        timeout: TimeInterval = 20) async throws {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/\(method)"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try RPCRequest(method: method, args: args).encoded()
        let (data, http) = try await self.http.data(for: urlRequest)
        if let error = DSHError.from(status: http.statusCode,
                                     message: String(data: data, encoding: .utf8)) {
            throw error
        }
        try RPCRequest.ok(from: data)
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
        return DSHDecoding.page(fromValue: value, requestedMax: maxMessages)
    }
}
