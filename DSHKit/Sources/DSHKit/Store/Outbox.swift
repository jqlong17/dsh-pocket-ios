import Foundation

/// 发件箱条目：已发出但服务端还没落成正式消息时用于显示/恢复/重发。
public struct OutboxEntry: Codable, Equatable, Sendable {
    public let rpcId: String
    public let sessionId: String
    public let text: String
    public let createdAt: Double
    public let mode: SendMode

    public init(rpcId: String, sessionId: String, text: String, createdAt: Double, mode: SendMode) {
        self.rpcId = rpcId
        self.sessionId = sessionId
        self.text = text
        self.createdAt = createdAt
        self.mode = mode
    }
}

public protocol OutboxStorage: AnyObject {
    func load() -> [OutboxEntry]
    func save(_ entries: [OutboxEntry])
}

public final class UserDefaultsOutboxStorage: OutboxStorage {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "dsh-pocket.outbox") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [OutboxEntry] {
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([OutboxEntry].self, from: data) else { return [] }
        return entries
    }

    public func save(_ entries: [OutboxEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}

/// 本地发件箱（模块 03）：持久化、TTL、按 rpcId 对账、按会话恢复。
public final class Outbox {
    private let storage: OutboxStorage
    private let ttl: TimeInterval
    private var entries: [OutboxEntry]

    public init(storage: OutboxStorage, ttl: TimeInterval = 10 * 60) {
        self.storage = storage
        self.ttl = ttl
        self.entries = storage.load()
        purgeExpired()
    }

    @discardableResult
    public func add(rpcId: String, sessionId: String, text: String, mode: SendMode,
                    now: TimeInterval = Date().timeIntervalSince1970) -> OutboxEntry {
        let entry = OutboxEntry(rpcId: rpcId, sessionId: sessionId, text: text, createdAt: now, mode: mode)
        entries.removeAll { $0.rpcId == rpcId }
        entries.append(entry)
        persist()
        return entry
    }

    public func confirm(rpcIds: Set<String>) {
        guard !rpcIds.isEmpty else { return }
        let ids = Set(rpcIds.compactMap { RPCId.normalized($0) })
        let before = entries.count
        entries.removeAll { ids.contains($0.rpcId.lowercased()) }
        if entries.count != before { persist() }
    }

    public func remove(rpcIds: Set<String>) {
        entries.removeAll { rpcIds.contains($0.rpcId) }
        persist()
    }

    public func purgeExpired(now: TimeInterval = Date().timeIntervalSince1970) {
        let before = entries.count
        entries.removeAll { now - $0.createdAt > ttl }
        if entries.count != before { persist() }
    }

    public func pending(sessionId: String) -> [OutboxEntry] {
        entries.filter { $0.sessionId == sessionId }
    }

    public func contains(rpcId: String) -> Bool {
        guard let normalized = RPCId.normalized(rpcId) else { return false }
        return entries.contains { $0.rpcId.lowercased() == normalized }
    }

    public var allEntries: [OutboxEntry] { entries }

    private func persist() { storage.save(entries) }
}

public final class InMemoryOutboxStorage: OutboxStorage {
    public var entries: [OutboxEntry]
    public init(entries: [OutboxEntry] = []) { self.entries = entries }
    public func load() -> [OutboxEntry] { entries }
    public func save(_ entries: [OutboxEntry]) { self.entries = entries }
}
