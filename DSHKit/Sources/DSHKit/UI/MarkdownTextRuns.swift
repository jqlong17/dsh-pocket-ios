import Foundation

/// 把块级 Markdown 分组为「可合并成一段文本」的 run。
///
/// 为什么需要：SwiftUI 的文本选择作用域是**单个 `Text`**
/// （`.textSelection` 只让容器里每个 `Text` 各自可选），所以「一块一个 `Text`」的渲染
/// 会让拖拽选择停在行内/列表项内，跨不了行（2026-11-24 用户反馈）。
/// 把连续的文本类块拼成**一个** AttributedString 放回一个 `Text`，选择才能连起来。
///
/// 哪些块能合并：段落 / 标题 / 列表项 / 引用——它们都是纯文本，样式可以写进 range。
/// 哪些不能：代码块（要底色与横向滚动）、表格（网格）、图片（独立视图）、分隔线。
/// 这些是**选择边界**，合并会让它们失去结构。
public enum MarkdownTextRun: Equatable, Sendable {
    /// 连续的文本类块，渲染成一个 `Text`。
    case text([MarkdownBlock])
    /// 必须独立渲染的块（同时是选择边界）。
    case block(MarkdownBlock)
}

public enum MarkdownTextRuns {
    /// 文本类块（可进同一个 `Text`）。
    public static func isTextBlock(_ block: MarkdownBlock) -> Bool {
        switch block {
        case .heading, .paragraph, .listItem, .quote:
            return true
        case .code, .table, .image, .divider:
            return false
        }
    }

    /// 按顺序分组：连续文本类块合成一个 `.text`，其余各自 `.block`。
    public static func group(_ blocks: [MarkdownBlock]) -> [MarkdownTextRun] {
        var runs: [MarkdownTextRun] = []
        var pending: [MarkdownBlock] = []

        func flush() {
            guard !pending.isEmpty else { return }
            runs.append(.text(pending))
            pending.removeAll()
        }

        for block in blocks {
            if isTextBlock(block) {
                pending.append(block)
            } else {
                flush()
                runs.append(.block(block))
            }
        }
        flush()
        return runs
    }

    /// 两个相邻块之间的分隔串。
    ///
    /// - 连续列表项用单换行：列表要紧凑，空行会把一个列表拆成好几段；
    /// - 连续引用行用单换行：解析器按行产出 quote 块，空行会把一段引用拆开；
    /// - 标题之后用单换行：标题属于它下面那段内容；
    /// - 其余用空行：等价于原来的块间距。
    public static func separator(previous: MarkdownBlock?, current: MarkdownBlock) -> String {
        guard let previous else { return "" }
        if case .listItem = previous, case .listItem = current { return "\n" }
        // 解析器按行产出 `.quote`，同一段引用是连续多个 quote 块；单换行让它们读成一段。
        if case .quote = previous, case .quote = current { return "\n" }
        if case .heading = previous { return "\n" }
        return "\n\n"
    }
}
