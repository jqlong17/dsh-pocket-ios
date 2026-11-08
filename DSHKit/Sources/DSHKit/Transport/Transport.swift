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
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw DSHError.invalidPayload }
            return (data, http)
        } catch let error as DSHError {
            throw error
        } catch {
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
