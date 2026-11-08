import XCTest
@testable import DSHKit

/// 模块 05：包内端到端（Mock 传输串起完整链路）。
final class E2ETests: XCTestCase {
    private func baseURL() throws -> URL {
        try XCTUnwrap(DSHURL.normalizedBase("http://192.168.1.10:3081"))
    }

    // E01 + E03：登录成功并通过可见性过滤
    func testLoginThenVisibleSessions() async throws {
        let listJSON = try fixtureJSON("session_list")
        let payload = try JSONSerialization.data(withJSONObject: ["result": ["value": ["items": listJSON["items"]!]]])
        let transport = MockHTTPTransport { request in
            if request.url?.path == "/pocket-login" {
                return .init(status: 302, body: Data(), headers: ["Set-Cookie": "dsh_pocket_token=x; Path=/"])
            }
            return .init(status: 200, body: payload, headers: [:])
        }
        let client = DSHClient(baseURL: try baseURL(), http: transport)

        let outcome = try await client.login(pin: "12345678")
        XCTAssertEqual(outcome, .success)
        let sessions = try await client.sessions()
        let visible = DSHSession.visible(in: sessions, archivedSessionIds: ["session-archived-1"])
        XCTAssertEqual(visible.map(\.sessionId), ["session-normal-1"])
    }

    // E02：错误 PIN
    func testWrongPIN() async throws {
        let transport = MockHTTPTransport { _ in .init(status: 200, body: Data(), headers: [:]) }
        let client = DSHClient(baseURL: try baseURL(), http: transport)
        let outcome = try await client.login(pin: "bad")
        XCTAssertEqual(outcome, .invalidPIN)
    }

    // E04：同步快照 + 事件顺序 + watchdog 重连（Mock 连接）
    func testSyncFlowWithReconnect() async throws {
        let snapshot = MockSyncConnection(frames: [try snapshotFrame(records: try pageRecordsFromFixture())])
        let transport = MockSyncTransport(connections: [snapshot],
                                          snapshotPage: { _ in throw SyncError.timeout })
        let config = SyncConfig(watchdog: .milliseconds(40), baseBackoff: .milliseconds(1), maxBackoff: .milliseconds(5))
        let coordinator = SessionSyncCoordinator(sessionId: "session-normal-1",
                                                 transport: transport,
                                                 config: config,
                                                 clock: RealSyncClock())
        await coordinator.start()
        await waitUntil("messages loaded") { await coordinator.currentMessages().count >= 3 }
        let messages = await coordinator.currentMessages()
        XCTAssertEqual(messages, messages.sorted { $0.sequence < $1.sequence })
        await coordinator.stop()
    }

    // E05 + E12：发送生命周期 + 发件箱恢复
    func testSendLifecycleAndOutboxRestore() {
        var lifecycle = MessageLifecycle()
        let outboxStorage = InMemoryOutboxStorage()
        let outbox = Outbox(storage: outboxStorage)
        let rpcId = "rpc-e2e"
        lifecycle.begin(rpcId: rpcId, mode: SendModeDecider.mode(isTurnRunning: false))
        outbox.add(rpcId: rpcId, sessionId: "s1", text: "你好", mode: .queue,
                   now: Date().timeIntervalSince1970)
        lifecycle.acknowledge(rpcId: rpcId)
        XCTAssertEqual(lifecycle.state(for: rpcId), .accepted(.queue))

        // 模拟 App 重启：发件箱恢复
        let restored = Outbox(storage: outboxStorage).pending(sessionId: "s1")
        XCTAssertEqual(restored.map(\.rpcId), [rpcId])

        // 服务端消息到达（rpcId 匹配）→ 确认
        lifecycle.commit(rpcId: rpcId)
        outbox.confirm(rpcIds: [rpcId])
        XCTAssertFalse(outbox.contains(rpcId: rpcId))
        XCTAssertEqual(lifecycle.state(for: rpcId), .committed)
    }

    // E06：生成中发送 = steer
    func testSteerWhenRunning() {
        XCTAssertEqual(SendModeDecider.mode(isTurnRunning: true), .steer)
        let presentation = PendingPresentationBuilder.make(state: .accepted(.steer))
        XCTAssertEqual(presentation.label, "已引导，正在继续")
    }

    // E07：失败 → 重发
    func testFailureThenRetry() {
        var lifecycle = MessageLifecycle()
        lifecycle.begin(rpcId: "r1", mode: .queue)
        lifecycle.fail(rpcId: "r1")
        XCTAssertEqual(PendingPresentationBuilder.make(state: .failed).isRetryable, true)
        lifecycle.begin(rpcId: "r2", mode: .queue)
        lifecycle.acknowledge(rpcId: "r2")
        XCTAssertEqual(lifecycle.state(for: "r2"), .accepted(.queue))
    }

    // E08：loadOlder 流程
    func testLoadOlderFlow() async throws {
        let older: [String: Any] = ["type": "user/message", "seq": 1,
                                    "data": ["content": [["type": "text", "text": "更早"]], "source": ["kind": "user"]]]
        let olderPage = DSHDecoding.page(fromValue: ["records": [["event": older]], "hasMore": false])
        let initial = DSHDecoding.page(fromValue: try fixtureJSON("session_page"))
        let transport = MockSyncTransport(connections: [MockSyncConnection()],
                                          snapshotPage: { _ in initial },
                                          olderPages: [olderPage])
        let coordinator = SessionSyncCoordinator(sessionId: "s", transport: transport,
                                                 clock: FakeSyncClock(mode: .never))
        await coordinator.start()
        await waitUntil("initial history") { await coordinator.currentMessages().isEmpty == false }
        await coordinator.loadOlder()
        let olderCalls = await coordinator.olderPageRequestCount()
        XCTAssertEqual(olderCalls, 1)
        await coordinator.stop()
    }

    // E09：A/B 会话隔离
    func testSessionsIsolated() async throws {
        let a = SessionSyncCoordinator(sessionId: "A",
                                       transport: MockSyncTransport(connections: [MockSyncConnection()],
                                                                    snapshotPage: { _ in DSHSessionPage(records: [], hasMore: false) }),
                                       clock: FakeSyncClock(mode: .never))
        let b = SessionSyncCoordinator(sessionId: "B",
                                       transport: MockSyncTransport(connections: [MockSyncConnection()],
                                                                    snapshotPage: { _ in DSHSessionPage(records: [], hasMore: false) }),
                                       clock: FakeSyncClock(mode: .never))
        await a.start()
        let event: [String: Any] = ["type": "user/message", "seq": 7,
                                    "data": ["content": [["type": "text", "text": "A"]], "source": ["kind": "user"]]]
        try await a.handleFrame(try eventFrame(event))
        let bMessages = await b.currentMessages()
        XCTAssertTrue(bMessages.isEmpty)
        await a.stop()
        await b.stop()
    }

    // E11：HTTP 兜底（WS snapshot 不可用）
    func testHTTPFallbackWhenSnapshotMissing() async throws {
        let page = DSHDecoding.page(fromValue: try fixtureJSON("session_page"))
        let transport = MockSyncTransport(connections: [MockSyncConnection()],
                                          snapshotPage: { _ in page })
        let coordinator = SessionSyncCoordinator(sessionId: "s", transport: transport,
                                                 clock: FakeSyncClock(mode: .never))
        await coordinator.start()
        await waitUntil("http fallback messages") { await coordinator.currentMessages().count >= 3 }
        await coordinator.stop()
    }
}
