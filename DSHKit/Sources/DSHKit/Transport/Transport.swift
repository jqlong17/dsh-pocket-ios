import Foundation

/// HTTP 传输抽象（可注入 Mock，模块 01/02）。
public protocol DSHHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// WebSocket 连接抽象。
public protocol DSHWebSocketConnection: Sendable {
    func send(text: String) async throws
    func receive() async throws -> Data
    func cancel()
}

public protocol DSHWebSocketTransport: Sendable {
    func connect(url: URL) async throws -> DSHWebSocketConnection
}

public struct DSHURLSessionHTTPTransport: DSHHTTPTransport {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let started = Date()
        func elapsedMs() -> Int { Int(Date().timeIntervalSince(started) * 1000) }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw DSHError.invalidPayload }
            HTTPTrace.shared.record(request, status: http.statusCode, ms: elapsedMs(), error: nil)
            return (data, http)
        } catch let error as URLError {
            // 记录网络层错误码：-1001 超时 / -1004 连不上 / -1022 ATS，修法完全不同。
            HTTPTrace.shared.record(request, status: nil, ms: elapsedMs(),
                                    error: "URLError \(error.code.rawValue)")
            // 不要包装：`URLError` 的错误码是「要不要重试 / 算不算断网」的唯一依据。
            // 曾经在这里包成 DSHError.transport，导致飞行模式下发消息被判定为
            // 「发送失败」而不是「断网暂存」，联网后也不会自动补发。
            throw error
        } catch let error as DSHError {
            throw error
        } catch {
            HTTPTrace.shared.record(request, status: nil, ms: elapsedMs(), error: "transport")
            throw DSHError.transport(error.localizedDescription)
        }
    }
}

public struct DSHURLSessionWebSocketTransport: DSHWebSocketTransport {
    private final class Connection: DSHWebSocketConnection, @unchecked Sendable {
        let task: URLSessionWebSocketTask
        init(task: URLSessionWebSocketTask) { self.task = task }

        func send(text: String) async throws { try await task.send(.string(text)) }

        func receive() async throws -> Data {
            let message = try await task.receive()
            switch message {
            case .string(let text): return Data(text.utf8)
            case .data(let data): return data
            @unknown default: throw DSHError.invalidPayload
            }
        }

        func cancel() { task.cancel(with: .goingAway, reason: nil) }
    }

    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func connect(url: URL) async throws -> DSHWebSocketConnection {
        let task = session.webSocketTask(with: url)
        task.resume()
        return Connection(task: task)
    }
}
