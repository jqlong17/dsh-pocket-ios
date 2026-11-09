import Foundation

/// 每个会话唯一的同步真相源：HTTP 基线 + WebSocket 增量 + 看门狗 + 重连 + 分页（模块 02）。
///
/// 设计要点：
/// - 按会话隔离（一个 coordinator 对应一个 sessionId），事件只进自己的状态；
/// - 事件按 seq 去重并检测跳号（跳号时补拉 HTTP 历史）；
/// - 连接失败指数退避重连；生成中无帧由 watchdog 主动断开；
/// - 对外只暴露 `updates`（AsyncStream），视图/store 不直接接触传输。
public actor SessionSyncCoordinator {
    public nonisolated let sessionId: String
    public nonisolated let updates: AsyncStream<SessionUpdate>

    private let transport: SyncTransport
    private let config: SyncConfig
    private let clock: SyncClock
    private let continuation: AsyncStream<SessionUpdate>.Continuation

    private var loopTask: Task<Void, Never>?
    private var connection: DSHWebSocketConnection?
    private var seenSeqs: Set<Int> = []
    private var messages: [DSHMessage] = []
    private var steps: [DSHStepEvent] = []
    private var emittedSnapshot = false
    private var lastSeq: Int?
    private var state: SyncConnectionState = .idle
    private var reconnectRequested = false
    /// 仅"本轮生成中"才启用看门狗：空闲会话不主动重连。
    private var expectingActivity = false
    private var olderPageRequests = 0
    private var hasMoreOlder = false

    public init(sessionId: String,
                transport: SyncTransport,
                config: SyncConfig = .default,
                clock: SyncClock = RealSyncClock()) {
        self.sessionId = sessionId
        self.transport = transport
        self.config = config
        self.clock = clock
        var continuation: AsyncStream<SessionUpdate>.Continuation!
        self.updates = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.continuation = continuation
    }

    // MARK: - Public API

    public func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
        connection?.cancel()
        connection = nil
        setState(.idle)
        continuation.finish()
    }

    /// 手动重连（UI「重连」按钮）。
    public func reconnect() {
        reconnectRequested = true
        connection?.cancel()
        connection = nil
    }

    public func loadOlder() async {
        guard let oldest = messages.map(\.sequence).min() else { return }
        olderPageRequests += 1
        do {
            let page = try await transport.olderPage(sessionId: sessionId,
                                                    beforeSeq: oldest,
                                                    maxMessages: config.maxMessages)
            hasMoreOlder = page.hasMore
            applyPage(page, emitSnapshot: false)
            emit(.hasMore(page.hasMore))
        } catch {
            // 分页失败不改变连接状态，等待下一次触发。
            emit(.hasMore(true))
        }
    }

    /// App 在收到 turn/start（或发送确认）时置 true，turn/end 时置 false。
    public func setExpectingActivity(_ value: Bool) {
        expectingActivity = value
    }

    public func currentState() -> SyncConnectionState { state }
    public func currentMessages() -> [DSHMessage] { messages }
    public func currentSteps() -> [DSHStepEvent] { steps }
    public func olderPageRequestCount() -> Int { olderPageRequests }
    public func currentHasMoreOlder() -> Bool { hasMoreOlder }

    // MARK: - Loop

    private func runLoop() async {
        var attempt = 0
        while !Task.isCancelled {
            reconnectRequested = false
            setState(attempt == 0 ? .connecting : .reconnecting(attempt: attempt))
            do {
                let connection = try await transport.openFollow(sessionId: sessionId,
                                                                maxMessages: config.maxMessages)
                self.connection = connection
                setState(.connected)
                attempt = 0
                // HTTP 基线（失败不致命，WS snapshot 可补）。
                if let page = try? await transport.snapshotPage(sessionId: sessionId,
                                                                maxMessages: config.maxMessages) {
                    applyPage(page, emitSnapshot: !emittedSnapshot)
                }
                try await receiveLoop(connection)
            } catch {
                connection?.cancel()
                connection = nil
                guard !Task.isCancelled else { break }
                attempt += 1
                setState(.reconnecting(attempt: attempt))
                let delay = backoffDelay(attempt: attempt)
                try? await clock.sleep(delay)
            }
        }
        setState(.disconnected(reason: nil))
    }

    private func backoffDelay(attempt: Int) -> Duration {
        let seconds = min(pow(2.0, Double(max(0, attempt - 1))), Double(config.maxBackoff.components.seconds))
        return .seconds(max(seconds, 1))
    }

    private func receiveLoop(_ connection: DSHWebSocketConnection) async throws {
        while !Task.isCancelled {
            let data: Data
            if expectingActivity {
                data = try await withTimeout(config.watchdog) {
                    try await connection.receive()
                }
            } else {
                data = try await connection.receive()
            }
            try? await handleFrame(data)
        }
    }

    private func withTimeout(_ duration: Duration, _ operation: @escaping () async throws -> Data) async throws -> Data {
        let clock = self.clock
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await clock.timeout(duration)
                throw SyncError.timeout
            }
            guard let first = try await group.next() else { throw SyncError.closed }
            group.cancelAll()
            return first
        }
    }

    // MARK: - Frames

    func handleFrame(_ data: Data) async throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let frame = DSHDecoding.streamFrame(fromJSON: json) {
            if case .textDelta(let attemptId, _, let text) = frame {
                emit(.assistantDelta(attemptId: attemptId, text: text))
            }
            return
        }
        let value = (json["value"] as? [String: Any]) ?? json
        if value["type"] as? String == "snapshot" {
            let records = value["records"] as? [[String: Any]] ?? []
            let page = DSHDecoding.page(fromValue: ["records": records,
                                                   "hasMore": value["hasMore"] as? Bool ?? false])
            applyPage(page, emitSnapshot: !emittedSnapshot)
            return
        }
        guard let event = value["event"] as? [String: Any] else { return }
        try applyEvent(event)
    }

    private func applyPage(_ page: DSHSessionPage, emitSnapshot: Bool) {
        for record in page.records {
            switch record {
            case .message(let message): mergeMessage(message)
            case .step(let step): mergeStep(step)
            case .title(let seq, let title): emit(.title(seq: seq, title: title))
            case .unknown: break
            }
        }
        if emitSnapshot {
            emittedSnapshot = true
            hasMoreOlder = page.hasMore
            emit(.snapshot(messages: messages.sorted { $0.sequence < $1.sequence },
                           steps: steps,
                           hasMore: page.hasMore))
        } else {
            emit(.messages(messages.sorted { $0.sequence < $1.sequence }))
        }
    }

    private func applyEvent(_ event: [String: Any]) throws {
        guard let seq = (event["seq"] as? NSNumber)?.intValue else { return }
        if seenSeqs.contains(seq) { return }                       // 幂等
        if let lastSeq, seq > lastSeq + 1 {
            // 跳号：补拉历史（一次），避免丢事件。
            Task { [weak self] in await self?.reloadHistory() }
        }
        seenSeqs.insert(seq)
        lastSeq = max(lastSeq ?? seq, seq)

        if let message = DSHDecoding.message(fromEvent: event) {
            mergeMessage(message)
            emit(.messages([message]))
            return
        }
        if let step = DSHDecoding.stepEvent(fromEvent: event) {
            mergeStep(step)
            emit(.step(step))
            return
        }
        if event["type"] as? String == "session/title",
           let data = event["data"] as? [String: Any],
           let title = data["title"] as? String {
            emit(.title(seq: seq, title: title))
        }
    }

    private func reloadHistory() async {
        guard emittedSnapshot else { return }
        if let page = try? await transport.snapshotPage(sessionId: sessionId,
                                                        maxMessages: config.maxMessages) {
            applyPage(page, emitSnapshot: false)
        }
    }

    private func mergeMessage(_ message: DSHMessage) {
        if let index = messages.firstIndex(where: { $0.sequence == message.sequence }) {
            messages[index] = message
        } else {
            messages.append(message)
            messages.sort { $0.sequence < $1.sequence }
        }
    }

    private func mergeStep(_ step: DSHStepEvent) {
        let seq: Int
        switch step {
        case .toolCall(let s, _, _, _, _, _): seq = s
        case .toolResult(let s, _, _, _, _, _): seq = s
        case .turnStart(let s, _): seq = s
        case .turnEnd(let s, _): seq = s
        }
        guard !steps.contains(where: { $0.sortSeq == seq && $0.tag == step.tag }) else { return }
        steps.append(step)
    }

    private func setState(_ newState: SyncConnectionState) {
        state = newState
        emit(.connection(newState))
    }

    private func emit(_ update: SessionUpdate) {
        continuation.yield(update)
    }
}

extension DSHStepEvent {
    var sortSeq: Int {
        switch self {
        case .toolCall(let s, _, _, _, _, _), .toolResult(let s, _, _, _, _, _),
             .turnStart(let s, _), .turnEnd(let s, _):
            return s
        }
    }

    var tag: String {
        switch self {
        case .toolCall: return "call"
        case .toolResult: return "result"
        case .turnStart: return "turnStart"
        case .turnEnd: return "turnEnd"
        }
    }
}
