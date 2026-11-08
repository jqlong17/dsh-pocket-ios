import Foundation

/// 协议客户端门面：登录 + RPC + 会话列表/历史（模块 01 提供基础能力，模块 02 在其上做同步）。
public final class DSHClient: @unchecked Sendable {
    public let baseURL: URL
    private let http: DSHHTTPTransport
    private let webSocket: DSHWebSocketTransport

    public init(baseURL: URL,
                http: DSHHTTPTransport = DSHURLSessionHTTPTransport(),
                webSocket: DSHWebSocketTransport = DSHURLSessionWebSocketTransport()) {
        self.baseURL = baseURL
        self.http = http
        self.webSocket = webSocket
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
    public func rpc(method: String, args: [String: Any]) async throws -> [String: Any] {
        let rpcId = UUID()
        let request = RPCRequest(method: method, rpcId: rpcId, args: args)
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/\(method)"))
        urlRequest.httpMethod = "POST"
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

    public func page(sessionId: String, maxMessages: Int) async throws -> DSHSessionPage {
        let value = try await rpc(method: "session/page", args: [
            "request": [
                "address": ["kind": "session", "sessionId": sessionId],
                "maxMessages": maxMessages
            ]
        ])
        return DSHDecoding.page(fromValue: value)
    }
}
