// MarkdownRenderer

import SwiftUI
import DSHKit
import UIKit

/// 自包含的 Markdown 渲染器：**不依赖 Textual**。
///
/// 为什么要有它：`Textual` 声明 `.iOS(.v18)`，想支持 iOS 17 就只能自己渲染。
/// 而项目里本来就有「精简模式」的块渲染器（`MessageRow.compactBlocks`），
/// 它已经能处理文本/表格/代码/图片——这里把它升级成唯一渲染器：
///
/// - **行内格式**交给 Foundation 的 `AttributedString(markdown:)`（iOS 15+），
///   粗体、斜体、行内代码、链接都能解析，不需要第三方；
/// - **块级结构**（标题、列表、引用、分隔线、代码块、表格、图片）自己按行判断。
///
/// ## 可选择的文本必须是一个 `Text`（2026-11-24）
///
/// `.textSelection(.enabled)` 只让**每个 `Text` 各自**可选，SwiftUI 没有跨视图选择。
/// 所以连续的文本类块（段落/标题/列表/引用）由 `MarkdownTextRuns` 分组后合并成
/// **一个** `AttributedString` 放进一个 `Text`，拖拽选择才能跨行、跨列表项、跨引用。
///
/// 代价（已在 `spec/2026-11-24-1855-select-across-blocks.md` 记录）：
/// 引用竖条变成每行前缀 `▍`（独立的竖条视图会把选择切断）；列表换行后续行
/// 不与正文对齐（文本流里做不了悬挂缩进）。
///
/// 与 Textual 相比的已知损失（用户可感知）：
/// - 代码块没有语法高亮（Textual 走 JavaScriptCore + Prism，复刻没意义）；
/// - 表格样式更朴素；
/// - 复杂嵌套（列表套列表、引用套代码）按平铺处理。
struct MarkdownRenderer: View, Equatable {
    let text: String
    var foreground: Color = .primary
    /// 是否已经展开（由外层控制「展开全部」按钮）。
    var isExpanded: Bool = false

    static func == (lhs: MarkdownRenderer, rhs: MarkdownRenderer) -> Bool {
        lhs.text == rhs.text && lhs.foreground == rhs.foreground && lhs.isExpanded == rhs.isExpanded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownTextRuns.group(MarkdownBlockParser.blocks(from: text)).enumerated()),
                    id: \.offset) { _, run in
                switch run {
                case .text(let blocks):
                    // 一个 run = 一个 Text = 一段连续的可选择文本。
                    Text(mergedText(blocks))
                case .block(let block):
                    blockView(block)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 把一个 run 里的文本块拼成一个 AttributedString（样式写进各自的 range）。
    private func mergedText(_ blocks: [MarkdownBlock]) -> AttributedString {
        var result = AttributedString()
        var previous: MarkdownBlock?
        for block in blocks {
            result.append(AttributedString(MarkdownTextRuns.separator(previous: previous, current: block)))
            result.append(attributed(block))
            previous = block
        }
        return result
    }

    /// 单个文本块的富文本。
    private func attributed(_ block: MarkdownBlock) -> AttributedString {
        switch block {
        case .heading(let level, let text):
            var heading = inlineAttributed(text)
            apply(font: level <= 2 ? .title3.weight(.semibold) : .headline, to: &heading)
            return heading

        case .paragraph(let text):
            return inlineAttributed(text)

        case .listItem(let marker, let text, let depth):
            var line = AttributedString(String(repeating: "  ", count: max(0, depth)))
            var markerText = AttributedString("\(marker) ")
            markerText.foregroundColor = foreground.opacity(0.6)
            line.append(markerText)
            line.append(inlineAttributed(text))
            return line

        case .quote(let text):
            // 引用竖条在「每行一个 `▍` 前缀」里重建：独立的竖条视图会切断选择。
            var quote = AttributedString()
            let lines = text.components(separatedBy: "\n")
            for (index, raw) in lines.enumerated() {
                if index > 0 { quote.append(AttributedString("\n")) }
                var bar = AttributedString("▍ ")
                bar.foregroundColor = foreground.opacity(0.45)
                quote.append(bar)
                var body = inlineAttributed(raw)
                body.foregroundColor = foreground.opacity(0.75)
                quote.append(body)
            }
            return quote

        case .code, .table, .image, .divider:
            // 这些块不进文本流（是选择边界），由 `blockView` 单独渲染。
            return AttributedString()
        }
    }

    private func apply(font: Font, to attributed: inout AttributedString) {
        for run in attributed.runs {
            attributed[run.range].font = font
        }
    }

    /// 代码块 / 表格 / 图片 / 分隔线：独立视图（同时也是选择边界）。
    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(foreground)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

        case .table(let header, let rows):
            MarkdownTable(header: header, rows: rows, tint: foreground)

        case .image(let destination, let alt):
            MarkdownImageBlock(destination: destination, alt: alt, tint: foreground)

        case .divider:
            Divider().opacity(0.4).padding(.vertical, 2)

        case .heading, .paragraph, .listItem, .quote:
            // 文本类块由 `mergedText(_:)` 处理，不会走到这里。
            EmptyView()
        }
    }

    /// 行内格式：把 Markdown 行内语法交给 Foundation 解析。
    ///
    /// `inlineOnlyPreservingWhitespace` 只解析 `**粗体**`、`*斜体*`、`` `code` ``、`[文字](链接)`，
    /// 保留原始空白与换行——正是我们要的（块级结构已经由解析器拆过）。
    ///
    /// **链接必须显式改色**：SwiftUI 默认用 accent 渲染链接，而用户的绿色气泡里
    /// accent 也是绿色 —— 链接文字直接融进背景（真机现象：用户发了一个邮箱地址，
    /// 气泡看起来是「空的」，其实是链接看不清，2026-11-24 反馈）。
    /// 所以这里把所有 run 的前景色统一成气泡前景色，链接另加下划线来区分。
    private func inlineAttributed(_ text: String) -> AttributedString {
        guard var attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            var plain = AttributedString(text)
            plain.foregroundColor = foreground
            return plain
        }
        for run in attributed.runs {
            let isLink = run.link != nil || run.attachment != nil
            attributed[run.range].foregroundColor = foreground
            if isLink {
                // 链接靠下划线表达「可以点」，而不是靠颜色（颜色已被气泡背景吃掉）。
                attributed[run.range].underlineStyle = .single
            }
        }
        return attributed
    }
}

/// 图片块：单独抽出来是因为它要访问 `ConnectionModel` 的 image URL 解析。
/// 通过环境拿不到，所以用 `@Environment` 不可行——这里保留为独立视图，
/// 由 `RemoteMarkdownImage` 自己处理 URL 解析失败的情况。
private struct MarkdownImageBlock: View {
    let destination: String
    let alt: String
    let tint: Color

    var body: some View {
        if let url = URL(string: destination), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            RemoteMarkdownImage(url: url, caption: alt.isEmpty ? nil : alt, allImageURLs: [])
                .frame(maxWidth: 320, alignment: .leading)
        } else {
            Text(alt.isEmpty ? "[图片]" : "[图片] \(alt)")
                .font(.footnote)
                .foregroundStyle(tint.opacity(0.6))
        }
    }
}

/// 极简表格：只求「看清内容」，不追求 GitHub 那套边框。
struct MarkdownTable: View {
    let header: [String]
    let rows: [[String]]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(header, isHeader: true)
            Divider().opacity(0.3)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, cells in
                row(cells, isHeader: false)
            }
        }
        .background(tint.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(tint.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func row(_ cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell)
                    .font(isHeader ? .footnote.weight(.semibold) : .footnote)
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
