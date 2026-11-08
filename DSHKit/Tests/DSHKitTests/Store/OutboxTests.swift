import XCTest
@testable import DSHKit

final class OutboxTests: XCTestCase {
    private func makeOutbox(now: TimeInterval = 1_000) -> Outbox {
        Outbox(storage: InMemoryOutboxStorage(), ttl: 600)
    }

    // M20：持久化恢复
    func testPersistenceAcrossInstances() {
        let storage = InMemoryOutboxStorage()
        let first = Outbox(storage: storage)
        first.add(rpcId: "r1", sessionId: "s1", text: "你好", mode: .steer,
                  now: Date().timeIntervalSince1970)
        let second = Outbox(storage: storage)
        XCTAssertEqual(second.pending(sessionId: "s1").map(\.rpcId), ["r1"])
    }

    // M21：TTL 清理
    func testExpiredEntriesArePurged() {
        let storage = InMemoryOutboxStorage()
        let outbox = Outbox(storage: storage, ttl: 600)
        outbox.add(rpcId: "old", sessionId: "s1", text: "旧", mode: .queue, now: 0)
        outbox.purgeExpired(now: 700)
        XCTAssertTrue(outbox.allEntries.isEmpty)
    }

    // M22：确认后移除
    func testConfirmRemovesEntry() {
        let outbox = makeOutbox()
        outbox.add(rpcId: "r1", sessionId: "s1", text: "a", mode: .queue, now: 1_000)
        outbox.confirm(rpcIds: ["r1"])
        XCTAssertFalse(outbox.contains(rpcId: "r1"))
    }

    // M23：失败条目保留（供重发）
    func testFailedEntryStaysForRetry() {
        let outbox = makeOutbox()
        outbox.add(rpcId: "r-fail", sessionId: "s1", text: "失败", mode: .queue, now: 1_000)
        // 未确认 = 仍在发件箱，UI 决定是否显示失败
        XCTAssertTrue(outbox.contains(rpcId: "r-fail"))
    }

    func testAddSameRpcIdReplaces() {
        let outbox = makeOutbox()
        outbox.add(rpcId: "r", sessionId: "s1", text: "a", mode: .queue, now: 1_000)
        outbox.add(rpcId: "r", sessionId: "s1", text: "b", mode: .steer, now: 1_001)
        XCTAssertEqual(outbox.pending(sessionId: "s1").count, 1)
        XCTAssertEqual(outbox.pending(sessionId: "s1").first?.text, "b")
    }

    func testUserDefaultsStorageRoundTrip() {
        let suite = "dshkit.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = UserDefaultsOutboxStorage(defaults: defaults)
        let outbox = Outbox(storage: storage)
        outbox.add(rpcId: "r1", sessionId: "s", text: "hi", mode: .steer, now: Date().timeIntervalSince1970)
        let reloaded = Outbox(storage: UserDefaultsOutboxStorage(defaults: defaults))
        XCTAssertEqual(reloaded.pending(sessionId: "s").count, 1)
        reloaded.remove(rpcIds: ["r1"])
        XCTAssertTrue(reloaded.allEntries.isEmpty)
    }

    func testRemoveAndContains() {
        let outbox = makeOutbox()
        outbox.add(rpcId: "r1", sessionId: "s", text: "a", mode: .queue, now: 1_000)
        XCTAssertTrue(outbox.contains(rpcId: "r1"))
        outbox.remove(rpcIds: ["r1"])
        XCTAssertFalse(outbox.contains(rpcId: "r1"))
    }

    func testPendingIsScopedToSession() {
        let outbox = makeOutbox()
        outbox.add(rpcId: "r1", sessionId: "s1", text: "a", mode: .queue, now: 1_000)
        outbox.add(rpcId: "r2", sessionId: "s2", text: "b", mode: .queue, now: 1_000)
        XCTAssertEqual(outbox.pending(sessionId: "s1").map(\.rpcId), ["r1"])
        XCTAssertEqual(outbox.pending(sessionId: "s2").map(\.rpcId), ["r2"])
    }
}
