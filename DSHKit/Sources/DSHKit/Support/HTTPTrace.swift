import Foundation

/// 一次 HTTP 请求的轻量记录（诊断用）。
///
/// 为什么记这个：连不上时，服务端只能看到「有没有请求到达」，
/// 看不到「App 认为它在请求什么、拿到了什么」。把 method / path / status /
/// 耗时 / 是否带 cookie 记下来，两边才能对齐排查（2026-11-27 的实际教训：
/// App 在切 Host 时只发了 HEAD / 和 POST /api/session/list，没有走 refresh，
/// 而服务端日志里只能看到前者）。
///
/// 刻意不记 body、不记查询串（query 里可能带 token），也不记完整 URL 的 host：
/// host 只保留主机名，字段够定位即可。
public struct HTTPTraceRecord: Sendable, Equatable {
    public let at: Date
    public let method: String
    public let host: String
    public let path: String
    public let status: Int?
    public let ms: Int
    public let hasAuth: Bool
    public let hasDevice: Bool
    public let error: String?

    public init(at: Date, method: String, host: String, path: String, status: Int?,
                ms: Int, hasAuth: Bool, hasDevice: Bool, error: String?) {
        self.at = at
        self.method = method
        self.host = host
        self.path = path
        self.status = status
        self.ms = ms
        self.hasAuth = hasAuth
        self.hasDevice = hasDevice
        self.error = error
    }
}

/// 请求轨迹的环形缓冲。纯逻辑，可单测；App 层只负责把它塞进诊断报告。
public final class HTTPTrace: @unchecked Sendable {
    public static let shared = HTTPTrace()

    public let capacity: Int
    private let lock = NSLock()
    private var records: [HTTPTraceRecord] = []

    public init(capacity: Int = 24) {
        self.capacity = capacity
    }

    public func record(_ request: URLRequest, status: Int?, ms: Int, error: String?) {
        let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
        let record = HTTPTraceRecord(
            at: Date(),
            method: (request.httpMethod ?? "GET").uppercased(),
            host: request.url?.host ?? "-",
            path: Self.redactedPath(request.url),
            status: status,
            ms: ms,
            hasAuth: cookie.contains("dsh-auth"),
            hasDevice: cookie.contains("dsh-pocket-device"),
            error: error
        )
        lock.lock()
        defer { lock.unlock() }
        records.append(record)
        if records.count > capacity {
            records.removeFirst(records.count - capacity)
        }
    }

    public func snapshot() -> [HTTPTraceRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        records.removeAll()
    }

    /// 只保留 path：查询串里可能有一次性 token，不该进诊断报告。
    static func redactedPath(_ url: URL?) -> String {
        guard let url else { return "-" }
        return url.path.isEmpty ? "/" : url.path
    }

    /// 一行摘要（诊断报告用）。
    public static func line(_ record: HTTPTraceRecord) -> String {
        let status = record.status.map(String.init) ?? "ERR"
        var text = "\(record.method) \(record.path) \(status)"
        text += " \(record.ms)ms"
        if record.hasAuth { text += " auth" }
        if record.hasDevice { text += " dev" }
        if let error = record.error, !error.isEmpty { text += " \(error)" }
        return text
    }

    public static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
