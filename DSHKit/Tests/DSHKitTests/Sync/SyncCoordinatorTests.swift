import XCTest
@testable import DSHKit

final class SyncCoordinatorTests: XCTestCase {
    private func messagesInFixture() throws -> [DSHMessage] {
        let page = DSHDecoding.page(fromValue: try fixtureJSON("session_page"))
        return page.records.compactMap { record -> DSHMessage? in
            if case .message(let message) = record { return message }
            return nil
        }
    }

    // S01：HTTP 基线失败，WS snapshot 仍能输出
    func testSnapshotFromWebSocketWhenHTTPFails() async throws {
        let connection = MockSyncConnection(frames: [try snapshotFrame(records: try pageRecordsFromFixture())])
        let transport = MockSyncTransport(connections: [connection], snapshotPage: { _ in throw SyncError.timeout })
        let coordinator = SessionSyncCoordinator(sessionId: "s", transport: transport,
                                                 clock: FakeSyncClock(mode: .never))
        await coordinator.start()
        await waitUntil("snapshot messages") { await coordinator.currentMessages().count >= 3 }
        let messages = await coordinator.currentMessages()
        XCTAssertEqual(messages.count, 3)
        await coordinator.stop()
    }

    // S02：snapshot 后事件增量追加，不重复
    func testEventsAfterSnapshot() async throws {
        let userEvent: [String: Any] = [
            "type": "user/message", "seq": 100,
            "data": ["content": [["type": "text", "text": "新消息"]],
                     "source": ["kind": "user", "rpcId": "RPC-X"]]
        ]
        let connection = MockSyncConnection(frames: [
            try snapshotFrame(records: try pageRecordsFromFixture()),
            try eventFrame(userEvent)
        ])
        let transport = MockSyncTransport(connections: [connection], snapshotPage: { _ in throw SyncError.timeout })
        let coordinator = SessionSyncCoordinator(sessionId: "s", transport: transport, clock: FakeSyncClock(mode: .never))
        await coordinator.start()
        await waitUntil("new message") { await coordinator.currentMessages().contains { $0.text == "新消息" } }
        let messages = await coordinator.currentMessages()
        XCTAssertEqual(messages.filter { $0.text == "新消息" }.count, 1)
        XCTAssertEqual(messages.last?.sequence, 100)
        await coordinator.stop()
    }

    // S03：重复事件按 seq 去重
    func testDuplicateEventIsIdempotent() async throws {
        let event: [String: Any] = [
            "type": "user/message", "seq": 50,
            "data": ["content": [["type": "text", "text": "重复"]],
                     "source": ["kind": "user"]]
        ]
        let connection = MockSyncConnection()
        let transport = MockSyncTransport(connections: [connection], snapshotPage: { _ in DSHSessionPage(records: [], hasMore: false) })
        let coordinator = SessionSyncCoordinator(sessionId: "s", transport: transport, clock: FakeSyncClock(mode: .never))
        await coordinator.start()
        try await coordinator.handleFrame(try eventFrame(event))
        try await coordinator.handleFrame(try eventFrame(event))
        let messages = await coordinator.currentMessages()
        XCTAssertEqual(messages.filter { $0.text == "重复" }.count, 1)
        await coordinator.stop()
    }

    // S04：HTTP 基线与 WS snapshot 同时存在时不重复
    func testHTTPAndWebSocketSnapshotDoNotDuplicate() async throws {
        let page = DSHDecoding.page(fromValue: try fixtureJSON("session_page"))
        let connection = MockSyncConnection(frames: [try snapshotFrame(records: try pageRecordsFromFixture())])
        let transport = MockSyncTransport(connections: [connection], snapshotPage: { _ in page })
        let coordinator = SessionSyncCoordinator(sessionId: "s", transport: transport, clock: FakeSyncClock(mode: .never))
        await coordinator.start()
        await waitUntil("messages") { await coordinator.currentMessages().count >= 3 }
        let messages = await coordinator.currentMessages()
        XCTAssertEqual(Set(messages.map(\.sequence)).count, messages.count)
        await coordinator.stop()
    }

    // S10：seq 跳号触发补拉
    func testSequenceGapTriggersReload() async throws {
        let connection = MockSyncConnection()
        let page = DSHDecoding.page(fromValue: try fixtureJSON("session_page"))
        var snapshotCalls = 0
        let transport = MockSyncTransport(connections: [connection], snapshotPage: { _ in
            snapshotCalls += 1
            return page
        })
        let coordinator = SessionSyncCoordinator(sessionId: "s", transport: transport, clock: FakeSyncClock(mode: .never))
        await coordinator.start()
        await waitUntil("initial history") { await coordinator.currentMessages().isEmpty == false }
        let before = snapshotCalls
        let first: [String: Any] = ["type": "user/message", "seq": 1000,
                                    "data": ["content": [["type": "text", "text": "a"]], "source": ["kind": "user"]]]
        let gap: [String: Any] = ["type": "user/message", "seq": 1004,
                                  "data": ["content": [["type": "text", "text": "b"]], "source": ["kind": "user"]]]
        try await coordinator.handleFrame(try eventFrame(first))
        try await coordinator.handleFrame(try eventFrame(gap))
        await waitUntil("reload called") { snapshotCalls > before }
        await coordinator.stop()
    }

    // S11：消息按 seq 排序
    func testMessagesSortedBySequence() async throws {
        let connection = MockSyncConnection()
        let transport = MockSyncTransport(connections: [connection], snapshotPage: { _ in DSHSessionPage(records: [], hasMore: false) })
        let coordinator = SessionSyncCoordinator(sessionId: "s", transport: transport, clock: FakeSyncClock(mode: .never))
        await coordinator.start()
        let later: [String: Any] = ["type": "user/message", "seq": 30,
                                    "data": ["content": [["type": "text", "text": "later"]], "source": ["kind": "user"]]]
        let earlier: [String: Any] = ["type": "user/message", "seq": 10,
                                      "data": ["content": [["type": "text", "text": "earlier"]], "source": ["kind": "user"]]]
        try await coordinator.handleFrame(try eventFrame(later))
        try await coordinator.handleFrame(try eventFrame(earlier))
        let messages = await coordinator.currentMessages()
        XCTAssertEqual(messages.map(\.text), ["earlier", "later"])
        await coordinator.stop()
    }

    // S20：连接成功状态
    func testConnectsAndReportsConnected() async throws {
        let transport = MockSyncTransport(connections: [MockSyncConnection()],
                                          snapshotPage: { _ in DSHSessionPage(records: [], hasMore: false) })
        let coordinator = SessionSyncCoordinator(sessionId: "s", transport: transport, clock: FakeSyncClock(mode: .never))
        await coordinator.start()
        await waitUntil("connected") { await coordinator.currentState() == .connected }
        await coordinator.stop()
    }

    // S21：生成中无帧，watchdog 触发重连
    func testWatchdogTriggersReconnect() async throws {
        let transport = MockSyncTransport(connections: [MockSyncConnection(), MockSyncConnection()],
                                          snapshotPage: { _ in DSHSessionPage(records: [], hasMore: false) })
        let config = SyncConfig(watchdog: .milliseconds(40), baseBackoff: .milliseconds(1), maxBackoff: .milliseconds(5))
        let coordinator = SessionSyncCoordinator(sessionId: "s", transport: transport,
                                                 config: config, clock: RealSyncClock())
        await coordinator.start()
        await coordinator.setExpectingActivity(true)
        await waitUntil("reconnect attempt") {
            if case .reconnecting = await coordinator.currentState() { return true }
            return false
        }
        await coordinator.stop()
    }

    // S22：打开失败时按退避重试
    func testBackoffWhenOpenFails() async throws {
        let clock = FakeSyncClock(mode: .never)
        let transport = MockSyncTransport(connections: [], openError: SyncError.closed,
                                          snapshotPage: { _ in DSHSessionPage(records: [], hasMore: false) })
        let coordinator = SessionSyncCoordinator(sessionId: "s", transport: transport, clock: clock)
        await coordinator.start()
        await waitUntil("backoff sleeps") { clock.sleeps.count >= 2 }
        XCTAssertGreaterThanOrEqual(transport.openCount, 2)
        await coordinator.stop()
    }

    // S23：重连成功后恢复数据
    func testReconnectRecoversAndDeliversSnapshot() async throws {
        let second = MockSyncConnection(frames: [try snapshotFrame(records: try pageRecordsFromFixture())])
        let transport = MockSyncTransport(connections: [MockSyncConnection(), second],
                                          snapshotPage: { _ in throw SyncError.timeout })
        let config = SyncConfig(watchdog: .milliseconds(40), baseBackoff: .milliseconds(1), maxBackoff: .milliseconds(5))
        let coordinator = SessionSyncCoordinator(sessionId: "s", transport: transport,
                                                 config: config, clock: RealSyncClock())
        await coordinator.start()
        await coordinator.setExpectingActivity(true)
        await waitUntil("recovered messages") { await coordinator.currentMessages().count > 0 }
        await coordinator.stop()
    }

    // S24：手动重连
    func testManualReconnect() async throws {
        let transport = MockSyncTransport(connections: [MockSyncConnection(), MockSyncConnection()],
                                          snapshotPage: { _ in DSHSessionPage(records: [], hasMore: false) })
        let coordinator = SessionSyncCoordinator(sessionId: "s", transport: transport, clock: FakeSyncClock(mode: .never))
        await coordinator.start()
        await waitUntil("connected") { await coordinator.currentState() == .connected }
        await coordinator.reconnect()
        await waitUntil("reopened") { transport.openCount >= 2 }
        await coordinator.stop()
    }

    // S42：空闲（非生成中）不触发看门狗
    func testIdleConnectionDoesNotReconnect() async throws {
        let transport = MockSyncTransport(connections: [MockSyncConnection(), MockSyncConnection()],
                                          snapshotPage: { _ in DSHSessionPage(records: [], hasMore: false) })
        let config = SyncConfig(watchdog: .milliseconds(30), baseBackoff: .milliseconds(1), maxBackoff: .milliseconds(5))
        let coordinator = SessionSyncCoordinator(sessionId: "s", transport: transport,
                                                 config: config, clock: RealSyncClock())
        await coordinator.start()
        await waitUntil("connected") { await coordinator.currentState() == .connected }
        try await Task.sleep(for: .milliseconds(120))
        let state = await coordinator.currentState()
        XCTAssertEqual(state, .connected)
        XCTAssertEqual(transport.openCount, 1)
        await coordinator.stop()
    }

    // S30：不同会话互不影响
    func testCoordinatorsAreIsolated() async throws {
        let transportA = MockSyncTransport(connections: [MockSyncConnection()], snapshotPage: { _ in DSHSessionPage(records: [], hasMore: false) })
        let transportB = MockSyncTransport(connections: [MockSyncConnection()], snapshotPage: { _ in DSHSessionPage(records: [], hasMore: false) })
        let a = SessionSyncCoordinator(sessionId: "A", transport: transportA, clock: FakeSyncClock(mode: .never))
        let b = SessionSyncCoordinator(sessionId: "B", transport: transportB, clock: FakeSyncClock(mode: .never))
        await a.start()
        let event: [String: Any] = ["type": "user/message", "seq": 1,
                                    "data": ["content": [["type": "text", "text": "A 的消息"]], "source": ["kind": "user"]]]
        try await a.handleFrame(try eventFrame(event))
        let bMessages = await b.currentMessages()
        XCTAssertTrue(bMessages.isEmpty)
        await a.stop()
    }

    // S31：stop 取消连接
    func testStopCancelsConnection() async throws {
        let connection = MockSyncConnection()
        let transport = MockSyncTransport(connections: [connection], snapshotPage: { _ in DSHSessionPage(records: [], hasMore: false) })
        let coordinator = SessionSyncCoordinator(sessionId: "s", transport: transport, clock: FakeSyncClock(mode: .never))
        await coordinator.start()
        await waitUntil("connected") { await coordinator.currentState() == .connected }
        await coordinator.stop()
        let state = await coordinator.currentState()
        XCTAssertEqual(state, .idle)
        XCTAssertTrue(connection.cancelled)
    }

    // S32：重启后保留历史，不重复全量拉取
    func testRestartKeepsHistoryWithoutRefetch() async throws {
        var fetches = 0
        let page = DSHDecoding.page(fromValue: try fixtureJSON("session_page"))
        let transport = MockSyncTransport(connections: [MockSyncConnection(), MockSyncConnection()],
                                          snapshotPage: { _ in
            fetches += 1
            return page
        })
        let coordinator = SessionSyncCoordinator(sessionId: "s", transport: transport, clock: FakeSyncClock(mode: .never))
        await coordinator.start()
        await waitUntil("history") { await coordinator.currentMessages().count >= 3 }
        await coordinator.stop()
        XCTAssertEqual(fetches, 1)
        let messages = await coordinator.currentMessages()
        XCTAssertEqual(messages.count, 3)
    }

    // S40：loadOlder 合并更早消息
    func testLoadOlderMerges() async throws {
        let olderMessage: [String: Any] = ["type": "user/message", "seq": 1,
                                           "data": ["content": [["type": "text", "text": "更早"]], "source": ["kind": "user"]]]
        let olderPage = DSHDecoding.page(fromValue: ["records": [["event": olderMessage]], "hasMore": false])
        let initial = DSHDecoding.page(fromValue: try fixtureJSON("session_page"))
        let transport = MockSyncTransport(connections: [MockSyncConnection()],
                                          snapshotPage: { _ in initial },
                                          olderPages: [olderPage])
        let coordinator = SessionSyncCoordinator(sessionId: "s", transport: transport, clock: FakeSyncClock(mode: .never))
        await coordinator.start()
        await waitUntil("initial history") { await coordinator.currentMessages().isEmpty == false }
        await coordinator.loadOlder()
        let calls = await coordinator.olderPageRequestCount()
        XCTAssertEqual(calls, 1)
        await coordinator.stop()
    }


    // DSHClient 作为 SyncTransport 的生产实现
    func testClientSyncTransportOpenFollowSendsOpenFrame() async throws {
        let ws = MockWebSocketTransport()
        let base = try XCTUnwrap(DSHURL.normalizedBase("http://192.168.1.10:3081"))
        let client = DSHClient(baseURL: base,
                               http: MockHTTPTransport { _ in .init(status: 200, body: Data(), headers: [:]) },
                               webSocket: ws)
        _ = try await client.openFollow(sessionId: "session-1", maxMessages: 30)
        let sent = try XCTUnwrap(ws.connection.sent.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(sent.utf8)) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "open")
        XCTAssertEqual(json["endpoint"] as? String, "session/follow")
    }

    func testClientSyncTransportPageDelegates() async throws {
        let payload = try JSONSerialization.data(withJSONObject: ["result": ["value": try fixtureJSON("session_page")]])
        let client = DSHClient(baseURL: try XCTUnwrap(DSHURL.normalizedBase("http://host:3081")),
                               http: MockHTTPTransport { _ in .init(status: 200, body: payload, headers: [:]) })
        let page = try await client.snapshotPage(sessionId: "s", maxMessages: 30)
        XCTAssertEqual(page.records.count, 10)
        let older = try await client.olderPage(sessionId: "s", beforeSeq: 1, maxMessages: 30)
        XCTAssertEqual(older.records.count, 10)
    }

    // S41：无消息时 loadOlder 不请求
    func testLoadOlderWithoutMessagesDoesNothing() async throws {
        let transport = MockSyncTransport(connections: [MockSyncConnection()],
                                          snapshotPage: { _ in DSHSessionPage(records: [], hasMore: false) })
        let coordinator = SessionSyncCoordinator(sessionId: "s", transport: transport, clock: FakeSyncClock(mode: .never))
        await coordinator.start()
        await coordinator.loadOlder()
        XCTAssertEqual(transport.olderPageCalls, 0)
        await coordinator.stop()
    }
}
