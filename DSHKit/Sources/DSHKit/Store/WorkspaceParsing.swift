import Foundation

/// 一个工作区（Host 上被 DSH 记账的目录）。
public struct WorkspaceSummary: Equatable, Identifiable, Sendable {
    public let workspaceId: String
    public let path: String
    public let title: String
    public let sessionCount: Int
    /// 该工作区里最新一条会话的更新时间（epoch 秒）。来自 `session/list`，
    /// 工作区自身不带这个字段——用它来排「最近活跃优先」。没有会话时为 nil。
    public var lastActiveAt: TimeInterval?

    public var id: String { workspaceId }

    public init(workspaceId: String, path: String, title: String, sessionCount: Int,
                lastActiveAt: TimeInterval? = nil) {
        self.workspaceId = workspaceId
        self.path = path
        self.title = title
        self.sessionCount = sessionCount
        self.lastActiveAt = lastActiveAt
    }
}

/// 解析 `workspace/follow` 的基线帧，以及「新建会话时预选哪个工作区」的判定。
public enum WorkspaceParsing {
    /// 从 baseline 帧里取出工作区列表。
    ///
    /// 形状：`{ "type": "baseline", "value": { "items": [ { workspaceId, path, title, sessionIds } ] } }`
    /// 缺 `workspaceId` 的项直接跳过——没有 id 就无法传给 `session/create`。
    public static func summaries(fromBaselineFrame frame: [String: Any]) -> [WorkspaceSummary] {
        guard let value = frame["value"] as? [String: Any],
              let items = value["items"] as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item in
            guard let workspaceId = item["workspaceId"] as? String,
                  !workspaceId.isEmpty else { return nil }
            let path = item["path"] as? String ?? ""
            let title = (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? Self.fallbackTitle(for: path)
            let sessionCount = (item["sessionIds"] as? [Any])?.count ?? 0
            return WorkspaceSummary(workspaceId: workspaceId, path: path,
                                    title: title, sessionCount: sessionCount)
        }
    }

    /// 从 `workspace/initializeDefault` 的返回里取默认工作区 id。
    ///
    /// 形状：`{ "workspace": { "workspaceId": "..." } }`
    public static func defaultWorkspaceId(fromInitialize value: [String: Any]) -> String? {
        guard let workspace = value["workspace"] as? [String: Any],
              let id = workspace["workspaceId"] as? String,
              !id.isEmpty else { return nil }
        return id
    }

    /// 新建会话时应预选哪个工作区。
    ///
    /// 优先级：上次用过的（仍在列表里）→ 默认工作区（仍在列表里）→ 列表第一项。
    /// 上次选择可能已被删除，所以每次都要校验存在性。
    public static func preselectedId(lastUsed: String?,
                                     defaultId: String?,
                                     available: [WorkspaceSummary]) -> String? {
        let ids = Set(available.map(\.workspaceId))
        if let lastUsed, ids.contains(lastUsed) { return lastUsed }
        if let defaultId, ids.contains(defaultId) { return defaultId }
        return available.first?.workspaceId
    }

    /// 路径最后一段作为标题（服务端没给 title 时用）。
    private static func fallbackTitle(for path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let last = (trimmed as NSString).lastPathComponent
        return last.isEmpty ? path : last
    }

    /// 选择器里的展示顺序：**默认工作区永远第一**，其余按最近活跃时间降序。
    ///
    /// 为什么默认工作区要固定第一：它是绝大多数会话的落点（本机 75/109 个会话在这里），
    /// 排后面每次都要往下找。其余按活跃度排，常用的项目自然浮上来。
    /// 没有活跃时间的（服务端有工作区但没有会话）排在最后，按标题升序，保证顺序稳定。
    public static func orderedForPicker(_ workspaces: [WorkspaceSummary],
                                        defaultId: String?) -> [WorkspaceSummary] {
        var pinned: WorkspaceSummary?
        var rest: [WorkspaceSummary] = []
        for workspace in workspaces {
            if workspace.workspaceId == defaultId {
                pinned = workspace
            } else {
                rest.append(workspace)
            }
        }
        rest.sort { lhs, rhs in
            switch (lhs.lastActiveAt, rhs.lastActiveAt) {
            case let (l?, r?):
                return l != r ? l > r : lhs.title < rhs.title
            case (nil, _?):
                return false   // 没活跃时间的排后面
            case (_?, nil):
                return true
            case (nil, nil):
                return lhs.title < rhs.title
            }
        }
        if let pinned { return [pinned] + rest }
        return rest
    }
}
