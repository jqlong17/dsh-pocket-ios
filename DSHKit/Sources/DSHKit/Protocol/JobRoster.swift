import Foundation

/// 一条后台任务（对应 DSH `job/list` 里的一行）。协议字段只在 DSHKit 里解析。
public struct DSHJobRow: Equatable, Sendable {
    public let id: String
    public let kind: String
    public let label: String
    public let status: String
    public let startedAt: Double
    public let finishedAt: Double?
    public let progress: String?
    public let detail: String?

    public init(id: String,
                kind: String,
                label: String,
                status: String,
                startedAt: Double,
                finishedAt: Double?,
                progress: String?,
                detail: String?) {
        self.id = id
        self.kind = kind
        self.label = label
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.progress = progress
        self.detail = detail
    }

    public init?(json: [String: Any]) {
        guard let id = json["id"] as? String, !id.isEmpty else { return nil }
        self.init(id: id,
                  kind: json["kind"] as? String ?? "",
                  label: json["label"] as? String ?? "",
                  status: json["status"] as? String ?? "",
                  startedAt: (json["startedAt"] as? NSNumber)?.doubleValue ?? 0,
                  finishedAt: (json["finishedAt"] as? NSNumber)?.doubleValue,
                  progress: json["progress"] as? String,
                  detail: json["detail"] as? String)
    }

    /// 还在跑（含正在停止）。
    public var isRunning: Bool { status == "running" || status == "stopping" }
}

/// `job/list` 是整份替换的流：一帧就是当前全量名单。
public enum DSHJobRoster {
    /// 从未知结构的帧里取名单；取不到返回 nil，表示这一帧不是名单，忽略即可。
    public static func rows(fromValue value: [String: Any]) -> [DSHJobRow]? {
        guard let raw = value["jobs"] as? [[String: Any]] else { return nil }
        return raw.compactMap(DSHJobRow.init(json:))
    }
}
