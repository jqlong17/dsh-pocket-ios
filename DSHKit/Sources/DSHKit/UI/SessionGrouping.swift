import Foundation

/// 会话列表的分组与排序。
///
/// 规则（原先内联在模型里，无测试）：
/// - 置顶单独成一组，永远在最上方，组内按置顶顺序；
/// - 其余按工作区目录（cwd）分组，组的顺序 = 目录在列表里首次出现的顺序；
/// - 没有 cwd 的会话归入「其他」。
public enum SessionGrouping {
    public struct Item: Equatable, Sendable {
        public let sessionId: String
        public let cwd: String?
        public init(sessionId: String, cwd: String?) {
            self.sessionId = sessionId
            self.cwd = cwd
        }
    }

    public struct Group: Equatable, Sendable {
        /// 置顶组用固定 id；其它组用目录路径。
        public let id: String
        /// 目录名（未本地化）；调用方负责把 "__pinned__" / "__other__" / "default-workspace" 翻成文案。
        public let folder: String?
        public let sessionIds: [String]
        public let isPinned: Bool
    }

    public static let pinnedGroupId = "__pinned__"
    public static let otherGroupId = "__other__"
    public static let defaultWorkspaceFolder = "default-workspace"

    public static func groups(items: [Item], pinnedIds: [String]) -> [Group] {
        var result: [Group] = []
        let byId = Dictionary(items.map { ($0.sessionId, $0) }, uniquingKeysWith: { first, _ in first })
        let pinned = pinnedIds.compactMap { byId[$0] }
        if !pinned.isEmpty {
            result.append(Group(id: pinnedGroupId, folder: nil,
                                sessionIds: pinned.map(\.sessionId), isPinned: true))
        }
        let pinnedSet = Set(pinnedIds)
        var order: [String] = []
        var buckets: [String: [String]] = [:]
        for item in items where !pinnedSet.contains(item.sessionId) {
            let path = item.cwd?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let key = path.isEmpty ? otherGroupId : path
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(item.sessionId)
        }
        for key in order {
            let folder: String? = key == otherGroupId ? nil : URL(fileURLWithPath: key).lastPathComponent
            result.append(Group(id: key, folder: folder, sessionIds: buckets[key] ?? [], isPinned: false))
        }
        return result
    }

    /// 展示顺序：置顶在前（按 pinnedIds 顺序），其余保持原顺序。
    public static func displayOrder(items: [Item], pinnedIds: [String]) -> [String] {
        guard !pinnedIds.isEmpty else { return items.map(\.sessionId) }
        let byId = Dictionary(items.map { ($0.sessionId, $0) }, uniquingKeysWith: { first, _ in first })
        let pinned = pinnedIds.compactMap { byId[$0]?.sessionId }
        let pinnedSet = Set(pinnedIds)
        return pinned + items.map(\.sessionId).filter { !pinnedSet.contains($0) }
    }
}
