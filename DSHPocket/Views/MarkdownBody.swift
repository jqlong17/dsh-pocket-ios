// MarkdownBody

import SwiftUI
import DSHKit

/// 消息体的 Markdown 渲染入口。
///
/// 实现委托给 `MarkdownRenderer`（自包含，不依赖 Textual）。
/// 这一层只负责两件与内容无关的事：
/// 1. **超长内容的折叠**（表格行数/代码行数超过阈值时先截断，给「展开全部」）；
/// 2. **Equatable**：会话里有几十条消息，滚动时任何状态变化都会重新求值，
///    只要 `text`/`foreground` 没变就跳过重建（真机实测这是内存波动的来源之一）。
struct MarkdownBody: View, Equatable {
    let text: String
    var foreground: Color = .primary
    /// 用户是否点了「展开全部」。默认折叠超长内容。
    @State private var expandAll = false

    static func == (lhs: MarkdownBody, rhs: MarkdownBody) -> Bool {
        lhs.text == rhs.text && lhs.foreground == rhs.foreground
    }

    var body: some View {
        // 超长的表格/代码块默认折叠：实测 100 行 × 8 列表格会把 footprint
        // 从 56 MB 推到 166 MB（CoreAnimation 16.7 MB / 937 个图层）。
        let truncated = expandAll
            ? MarkdownTruncation.Result(markdown: text, omittedTableRows: 0, omittedCodeLines: 0)
            : MarkdownTruncation.apply(to: text)

        VStack(alignment: .leading, spacing: 6) {
            MarkdownRenderer(text: truncated.markdown, foreground: foreground, isExpanded: expandAll)

            if truncated.didTruncate && !expandAll {
                Button {
                    expandAll = true
                } label: {
                    Text(L10n.tf("展开全部（另有 %d 行）", truncated.omittedTotal))
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
}
