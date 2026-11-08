import Foundation
import XCTest
@testable import DSHKit

final class MockSyncConnection: DSHWebSocketConnection, @unchecked Sendable {
    private var frames: [Data]
    private(set) var cancelled = false

    init(frames: [Data] = []) { self.frames = frames }

    func send(text: String) async throws {}

    func receive() async throws -> Data {
        if !frames.isEmpty { return frames.removeFirst() }
        // 空闲连接：阻塞直到被取消（模拟真实长连接）。
        while !cancelled, !Task.isCancelled {
            try await Task.sleep(for: .milliseconds(10))
        }
        throw SyncError.closed
    }

    func cancel() { cancelled = true }
}

final class MockSyncTransport: SyncTransport, @unchecked Sendable {
    private var connections: [MockSyncConnection]
    private var openError: Error?
    let snapshotPage: (Int) throws -> DSHSessionPage
    private(set) var openCount = 0
    private(set) var snapshotPageCalls = 0
    private(set) var olderPageCalls = 0
    private var olderPages: [DSHSessionPage]

    init(connections: [MockSyncConnection] = [MockSyncConnection()],
         openError: Error? = nil,
         snapshotPage: @escaping (Int) throws -> DSHSessionPage = { _ in DSHSessionPage(records: [], hasMore: false) },
         olderPages: [DSHSessionPage] = []) {
        self.connections = connections
        self.openError = openError
        self.snapshotPage = snapshotPage
        self.olderPages = olderPages
    }

    func openFollow(sessionId: String, maxMessages: Int) async throws -> DSHWebSocketConnection {
        openCount += 1
        if let openError { throw openError }
        guard !connections.isEmpty else { throw SyncError.closed }
        return connections.removeFirst()
    }

    func snapshotPage(sessionId: String, maxMessages: Int) async throws -> DSHSessionPage {
        snapshotPageCalls += 1
        return try snapshotPage(snapshotPageCalls)
    }

    func olderPage(sessionId: String, beforeSeq: Int, maxMessages: Int) async throws -> DSHSessionPage {
        olderPageCalls += 1
        guard !olderPages.isEmpty else { return DSHSessionPage(records: [], hasMore: false) }
        return olderPages.removeFirst()
    }

    func enqueueConnection(_ connection: MockSyncConnection) { connections.append(connection) }
}

final class FakeSyncClock: SyncClock, @unchecked Sendable {
    enum TimeoutMode { case throwImmediately, never }
    private let mode: TimeoutMode
    private(set) var sleeps: [Duration] = []

    init(mode: TimeoutMode = .never) { self.mode = mode }

    func sleep(_ duration: Duration) async throws { sleeps.append(duration) }

    func timeout(_ duration: Duration) async throws {
        switch mode {
        case .throwImmediately: throw SyncError.timeout
        case .never:
            try await Task.sleep(for: .seconds(3600))
            throw SyncError.timeout
        }
    }

    func now() -> Date { Date() }
}

func itemFrame(_ value: [String: Any], streamId: String = "s1") throws -> Data {
    try JSONSerialization.data(withJSONObject: ["type": "item", "streamId": streamId, "value": value])
}

func snapshotFrame(records: [[String: Any]], hasMore: Bool = false) throws -> Data {
    try itemFrame(["type": "snapshot", "records": records, "hasMore": hasMore])
}

func eventFrame(_ event: [String: Any]) throws -> Data {
    try itemFrame(["type": "event", "event": event])
}

func pageRecordsFromFixture() throws -> [[String: Any]] {
    let json = try fixtureJSON("session_page")
    return try XCTUnwrapCast(json["records"] as? [[String: Any]])
}

private func XCTUnwrapCast<T>(_ value: T?) throws -> T {
    guard let value else { throw DSHError.invalidPayload }
    return value
}

extension XCTestCase {
    func waitUntil(_ description: String = "condition", timeout: TimeInterval = 2,
                   file: StaticString = #filePath, line: UInt = #line,
                   _ condition: @escaping () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timeout waiting for \(description)", file: file, line: line)
    }
}
