import Foundation

/// 过程展开后给用户看的短文。不把工具原文里的标签和长路径原样贴出来。
public enum ProcessResultSummary {
    public static func display(tool: String, raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if let file = unwrapFile(trimmed) { return file }
        if tool == "grep" || trimmed.contains("Found ") {
            return summarizeSearch(trimmed)
        }
        return clip(stripTags(trimmed), lines: 3)
    }

    /// 路径只留文件名。本来就不是路径的原样返回。
    public static func shortPath(_ detail: String) -> String {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("/") else { return trimmed }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    static func unwrapFile(_ raw: String) -> String? {
        guard raw.contains("<type>") || raw.contains("<content>") || raw.contains("<path>") else { return nil }
        let type = tag("type", in: raw) ?? "file"
        let kind = type == "directory" ? "目录" : "文件"
        let content = tag("content", in: raw)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if content.isEmpty || content == "..." || content.hasPrefix("...") {
            return "\(kind)，正文已省略"
        }
        let preview = clip(stripTags(content), lines: 2)
        if preview.isEmpty { return "\(kind)，正文已省略" }
        return "\(kind)\n\(preview)"
    }

    static func summarizeSearch(_ raw: String) -> String {
        let text = stripTags(raw)
        var headline = "搜索结果"
        if let match = text.range(of: #"Found\s+(\d+)\s+match"#, options: .regularExpression) {
            let line = String(text[match])
            let digits = line.filter(\.isNumber)
            if let count = Int(digits) {
                headline = count == 0 ? "没有匹配" : "\(count) 处匹配"
            }
        }
        let hits = text.split(separator: "\n").map(String.init).filter {
            $0.contains("Line ") || $0.contains(":") && !$0.hasPrefix("/")
        }
        let preview = hits.prefix(2).joined(separator: "\n")
        if preview.isEmpty { return headline }
        return headline + "\n" + preview
    }

    static func tag(_ name: String, in raw: String) -> String? {
        let open = "<\(name)>"
        let close = "</\(name)>"
        guard let start = raw.range(of: open)?.upperBound else { return nil }
        if let end = raw.range(of: close, range: start..<raw.endIndex)?.lowerBound {
            return String(raw[start..<end])
        }
        return String(raw[start...])
    }

    static func stripTags(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"</?[A-Za-z][^>]*>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func clip(_ text: String, lines: Int) -> String {
        let kept = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(lines)
            .map { $0.count > 80 ? String($0.prefix(80)) + "…" : $0 }
        return kept.joined(separator: "\n")
    }
}
