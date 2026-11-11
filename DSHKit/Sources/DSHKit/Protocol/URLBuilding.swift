import Foundation

/// 地址规范化与 WebSocket URL 构造（模块 01 / 用例 P01–P02）。
public enum DSHURL {
    private static let zeroWidthCharacters: Set<Character> = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}"]

    /// 规范化用户输入的服务器地址：去空白/零宽字符、缺 scheme 时补 `http://`。
    public static func normalizedBase(_ address: String) -> URL? {
        var cleaned = address
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if !cleaned.lowercased().hasPrefix("http://"), !cleaned.lowercased().hasPrefix("https://") {
            cleaned = "http://" + cleaned
        }
        guard let url = URL(string: cleaned), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// 构造 WebSocket URL；path 不带前导斜杠时自动补上（历史 bug：缺 `/` 导致 URLComponents.url 返回 nil）。
    public static func webSocketURL(from base: URL, path: String) -> URL? {
        guard let baseHost = base.host, !baseHost.isEmpty,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        switch components.scheme?.lowercased() {
        case "https": components.scheme = "wss"
        case "http": components.scheme = "ws"
        default: break
        }
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        components.path = normalizedPath
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// 去掉 query 与 fragment 的地址，用于保存和比较；扫码地址里的配对 token 不会留在这里。
    public static func baseAddress(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.host ?? ""
        }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.string ?? (url.host ?? "")
    }

    /// 写日志用的地址。查询串和片段一律不写，避免把 token 带进日志和诊断文件。
    public static func redacted(_ url: URL) -> String {
        let hadSecrets = URLComponents(url: url, resolvingAgainstBaseURL: false)
            .map { $0.query != nil || $0.fragment != nil } ?? false
        let base = baseAddress(url)
        return hadSecrets ? base + "（参数已省略）" : base
    }

    /// 同上，但输入是可能带参数、甚至无法解析的原始字符串。
    public static func redactedAddress(_ raw: String) -> String {
        guard let url = URL(string: raw), let host = url.host, !host.isEmpty else {
            return "（地址无法解析）"
        }
        return redacted(url)
    }
}
