import Foundation

/// 实时连接状态（模块 02）。
public enum SyncConnectionState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case disconnected(reason: String?)

    public var isConnected: Bool { self == .connected }
}

/// 协调者输出的增量（视图/Store 消费）。
public enum SessionUpdate: Equatable, Sendable {
    case snapshot(messages: [DSHMessage], steps: [DSHStepEvent], hasMore: Bool)
    case messages([DSHMessage])
    case step(DSHStepEvent)
    case title(seq: Int, title: String)
    case assistantDelta(attemptId: String, text: String)
    case connection(SyncConnectionState)
    /// 更早历史是否还有（true = 还能继续 loadOlder）。
    case hasMore(Bool)
}

public struct SyncConfig: Sendable {
    public var maxMessages: Int
    public var watchdog: Duration
    public var baseBackoff: Duration
    public var maxBackoff: Duration
    public var pollInterval: Duration
    /// 首次连上时要不要再走一次 HTTP 基线。
    /// 会话内容已经在内存里（再次进入同一条会话）时置 false：只靠 WS 快照补齐，少拉一次整页。
    public var fetchHTTPBaseline: Bool

    public init(maxMessages: Int = 30,
                watchdog: Duration = .seconds(25),
                baseBackoff: Duration = .seconds(1),
                maxBackoff: Duration = .seconds(15),
                pollInterval: Duration = .seconds(5),
                fetchHTTPBaseline: Bool = true) {
        self.maxMessages = maxMessages
        self.watchdog = watchdog
        self.baseBackoff = baseBackoff
        self.maxBackoff = maxBackoff
        self.pollInterval = pollInterval
        self.fetchHTTPBaseline = fetchHTTPBaseline
    }

    public static let `default` = SyncConfig()
}

public enum SyncError: Error, Equatable, Sendable {
    case timeout
    case closed
    case protocolViolation(String)
}

/// 可注入时钟：让看门狗/退避在测试中即时完成。
public protocol SyncClock: Sendable {
    func sleep(_ duration: Duration) async throws
    /// 超时竞速：超时抛 `SyncError.timeout`。
    func timeout(_ duration: Duration) async throws
    func now() -> Date
}

public struct RealSyncClock: SyncClock {
    public init() {}
    public func sleep(_ duration: Duration) async throws { try await Task.sleep(for: duration) }
    public func timeout(_ duration: Duration) async throws {
        try await Task.sleep(for: duration)
        throw SyncError.timeout
    }
    public func now() -> Date { Date() }
}

/// 协调者依赖的传输抽象（可 Mock）。
public protocol SyncTransport: Sendable {
    func snapshotPage(sessionId: String, maxMessages: Int) async throws -> DSHSessionPage
    func openFollow(sessionId: String, maxMessages: Int) async throws -> DSHWebSocketConnection
    func olderPage(sessionId: String, beforeSeq: Int, maxMessages: Int) async throws -> DSHSessionPage
}
