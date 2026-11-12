import Foundation

/// 把「一条消息里的 Markdown」切成文本段与图片段。
///
/// 为什么要下沉到这里：这是纯字符串处理，App 层没有单测 target，
/// 放在视图/模型里等于无法测试（spec/12：判断可测、IO 隔离）。
/// 只有「独立成行的 `![说明](地址)`」才算图片，行内图片仍按文本渲染。
public enum MarkdownSegment: Equatable, Sendable {
    case text(String)
    case image(URL, caption: String?)
}

public enum MarkdownSegments {
    private static let imageLine = try? NSRegularExpression(pattern: #"^!\[([^\]]*)\]\(([^)\s]+)\)$"#)

    /// - Parameters:
    ///   - markdown: 原始 Markdown。
    ///   - resolve: 把图片地址变成可加载 URL 的解析器（相对路径需要会话 cwd，属于调用方知识）。
    public static func split(_ markdown: String,
                             resolve: (String) -> URL?) -> [MarkdownSegment] {
        guard markdown.contains("![") else { return [.text(markdown)] }
        var segments: [MarkdownSegment] = []
        var buffer: [String] = []

        func flushText() {
            let joined = buffer.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.text(joined))
            }
            buffer.removeAll()
        }

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let regex = imageLine,
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let captionRange = Range(match.range(at: 1), in: trimmed),
               let destinationRange = Range(match.range(at: 2), in: trimmed) {
                let caption = String(trimmed[captionRange])
                let destination = String(trimmed[destinationRange])
                if let url = resolve(destination) {
                    flushText()
                    segments.append(.image(url, caption: caption.isEmpty ? nil : caption))
                    continue
                }
            }
            buffer.append(line)
        }
        flushText()
        return segments.isEmpty ? [.text(markdown)] : segments
    }
}
