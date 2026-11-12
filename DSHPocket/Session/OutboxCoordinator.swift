// OutboxCoordinator

import Foundation
import DSHKit
import Observation

/// 发件箱的唯一真相：未确认正文、断网标记、补发进度。
///
/// 边界（spec/12）：
/// - 只持有「还没被服务端确认的发送」和它们的磁盘副本；
/// - 不发网络、不改会话气泡。补发、重试、把标记灌进会话，仍由 ConnectionModel 编排，
///   通过本类型读写条目。这样「改发送不会碰到连接」才成立。
/// - 图片本体在 `OutboxImageStore`，这里只记附件元数据；确认或取消时一并回收磁盘。
@Observable
final class OutboxCoordinator {
    static let defaultsKey = "dsh-pocket.send-outbox"

    /// 未确认条目。服务端历史确认前不得删除（见 `OutboxRetentionPolicy`）。
    private(set) var entries: [OutboxEntry] = []
    private(set) var loaded = false
    /// 补发进行中。防止列表刷新和实时流恢复同时补发同一批。
    var flushInFlight = false
    /// 输入栏上方的进度文案；全部补完由调用方清空。
    var flushNote: String?

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([OutboxEntry].self, from: data) else { return }
        // 不按时间删除。断网暂存和未确认正文一直留到服务端历史确认。
        // 附件元数据必须带上：重启后补发还要读磁盘上的图（曾经漏掉，重启即丢图）。
        entries = decoded.map {
            OutboxEntry(id: $0.id.lowercased(), sessionId: $0.sessionId,
                        text: $0.text, createdAt: $0.createdAt,
                        heldOffline: $0.heldOffline, sendFailed: $0.sendFailed,
                        accepted: $0.accepted, attachments: $0.attachments,
                        autoRetried: $0.autoRetried)
        }
        persist()
    }

    func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    func append(_ entry: OutboxEntry) {
        loadIfNeeded()
        entries.append(entry)
        persist()
    }

    @discardableResult
    func update(rpcId: String, _ change: (inout OutboxEntry) -> OutboxEntry?) -> Bool {
        loadIfNeeded()
        let id = rpcId.lowercased()
        guard let index = entries.firstIndex(where: { $0.id.lowercased() == id }) else { return false }
        var entry = entries[index]
        guard let updated = change(&entry) else { return false }
        entries[index] = updated
        persist()
        return true
    }

    /// 删条目并回收图片目录。返回实际删掉的条数。
    @discardableResult
    func remove(rpcIds: Set<String>, deleteImages: Bool = true) -> Int {
        guard !rpcIds.isEmpty else { return 0 }
        loadIfNeeded()
        let ids = Set(rpcIds.map { $0.lowercased() })
        let before = entries.count
        entries.removeAll { ids.contains($0.id.lowercased()) }
        let removed = before - entries.count
        if removed > 0 {
            persist()
            if deleteImages { ids.forEach(OutboxImageStore.delete(rpcId:)) }
        }
        return removed
    }

    /// 连接恢复后要补发的条目：断网暂存 + 首次失败的。
    func resendCandidates() -> [OutboxEntry] {
        loadIfNeeded()
        return entries.filter {
            SendRetryPolicy.shouldAutoResend(heldOffline: $0.heldOffline,
                                             sendFailed: $0.sendFailed,
                                             accepted: $0.accepted,
                                             autoRetried: $0.autoRetried)
        }.sorted { $0.createdAt < $1.createdAt }
    }

    /// 标记「已经自动重试过」，避免永久失败的消息每轮连接都重试。
    func markAutoRetried(rpcId: String) {
        update(rpcId: rpcId) { entry in
            guard !entry.autoRetried else { return nil }
            entry.autoRetried = true
            return entry
        }
    }

    func contains(rpcId: String, where matches: (OutboxEntry) -> Bool) -> Bool {
        let id = rpcId.lowercased()
        return entries.contains { $0.id.lowercased() == id && matches($0) }
    }

    func entry(rpcId: String) -> OutboxEntry? {
        let id = rpcId.lowercased()
        return entries.first { $0.id.lowercased() == id }
    }
}
