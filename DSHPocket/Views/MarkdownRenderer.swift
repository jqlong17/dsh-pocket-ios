// MarkdownRenderer

import SwiftUI
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
            ForEach(Array(MarkdownBlockParser.blocks(from: text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(level <= 2 ? .title3.weight(.semibold) : .headline)
                .padding(.top, level <= 2 ? 6 : 2)

        case .paragraph(let text):
            inline(text)

        case .listItem(let marker, let text, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(foreground.opacity(0.6))
                inline(text)
            }
            .padding(.leading, CGFloat(depth) * 14)

        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(foreground.opacity(0.25))
                    .frame(width: 3)
                inline(text)
                    .foregroundStyle(foreground.opacity(0.75))
            }

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
        }
    }

    /// 行内格式：把 Markdown 行内语法交给 Foundation 解析。
    ///
    /// `inlineOnlyPreservingWhitespace` 只解析 `**粗体**`、`*斜体*`、`` `code` ``、`[文字](链接)`，
    /// 保留原始空白与换行——正是我们要的（块级结构已经由解析器拆过了）。
    private func inline(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed).foregroundColor(foreground)
        }
        return Text(text).foregroundColor(foreground)
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

// MARK: - 解析

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case listItem(marker: String, text: String, depth: Int)
    case quote(String)
    case code(String)
    case table(header: [String], rows: [[String]])
    case image(destination: String, alt: String)
    case divider
}

enum MarkdownBlockParser {
    /// 按行解析成块。**只做行级判断**，不做完整语法树——
    /// 这是滑动性能的关键（会话里几十条消息，每条都要在滚动中反复求值）。
    static func blocks(from raw: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var inCode = false
        var listDepthStack: [Int] = []

        func flushParagraph() {
            let text = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraphLines.removeAll()
        }

        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 代码围栏：内部原样保留（含空行）
            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inCode = false
                } else {
                    flushParagraph()
                    inCode = true
                }
                continue
            }
            if inCode {
                codeLines.append(line)
                continue
            }

            // 空行 = 段落分隔
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            // 分隔线
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.divider)
                continue
            }

            // 标题
            if let match = heading(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: match.level, text: match.text))
                continue
            }

            // 独占一行的图片
            if let image = standaloneImage(trimmed) {
                flushParagraph()
                blocks.append(.image(destination: image.destination, alt: image.alt))
                continue
            }

            // 引用
            if trimmed.hasPrefix(">") {
                flushParagraph()
                let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(.quote(body))
                continue
            }

            // 列表：按缩进算层级，只记录最简层级（平铺）
            if let item = listItem(line) {
                flushParagraph()
                let depth = min(item.depth, 3)
                listDepthStack.append(depth)
                blocks.append(.listItem(marker: item.marker, text: item.text, depth: depth))
                continue
            }

            // 表格：以 | 开头且下一行是分隔行 —— 由调用方按连续块处理
            if trimmed.hasPrefix("|") {
                flushParagraph()
                // 收集连续的表格行
                // （这里用一次扫描：把这段交给 parseTable 处理，返回剩余行）
                // 为保持简单，表格在下面单独一趟处理。
                blocks.append(.paragraph(trimmed))  // 占位，稍后替换
                continue
            }

            paragraphLines.append(trimmed)
        }

        if inCode, !codeLines.isEmpty {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        flushParagraph()

        return mergingTables(blocks)
    }

    /// 把「段落形式的表格行」合并成真正的表格块。
    ///
    /// 为什么放到第二趟：表格需要「分隔行」来判断表头，且要按列切分，
    /// 混在第一趟的行循环里会让状态机更难读。
    private static func mergingTables(_ blocks: [MarkdownBlock]) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var pendingTableLines: [String] = []

        func flushTable() {
            guard !pendingTableLines.isEmpty else { return }
            if let table = parseTable(pendingTableLines) {
                result.append(.table(header: table.header, rows: table.rows))
            } else {
                // 不是合法表格：按普通段落还原，避免内容丢失
                result.append(.paragraph(pendingTableLines.joined(separator: "\n")))
            }
            pendingTableLines.removeAll()
        }

        for block in blocks {
            if case .paragraph(let text) = block, text.hasPrefix("|") {
                pendingTableLines.append(text)
            } else {
                flushTable()
                result.append(block)
            }
        }
        flushTable()
        return result
    }

    private static func parseTable(_ lines: [String]) -> (header: [String], rows: [[String]])? {
        guard lines.count >= 2 else { return nil }
        let header = cells(in: lines[0])
        guard !header.isEmpty else { return nil }
        // 第二行必须是分隔行（--- 或 :---:）
        let separator = cells(in: lines[1])
        let isSeparator = !separator.isEmpty && separator.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && trimmed.allSatisfy { $0 == "-" || $0 == ":" }
        }
        guard isSeparator else { return nil }
        let rows = lines.dropFirst(2).map { cells(in: $0) }
        return (header, rows)
    }

    private static func cells(in line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6 else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.hasPrefix(" ") else { return nil }
        return (hashes.count, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func listItem(_ line: String) -> (marker: String, text: String, depth: Int)? {
        // 缩进层级：每 2 个空格算一层（稳妥，不追求规范）
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        let depth = leading.filter { $0 == " " }.count / 2
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        for bullet in ["- ", "* ", "+ "] where trimmed.hasPrefix(bullet) {
            return ("•", String(trimmed.dropFirst(bullet.count)), depth)
        }
        // 有序列表：`1. ` / `12) `
        if let dot = trimmed.firstIndex(where: { $0 == "." || $0 == ")" }) {
            let number = trimmed[trimmed.startIndex..<dot]
            if !number.isEmpty, number.allSatisfy(\.isNumber),
               trimmed.index(after: dot) < trimmed.endIndex,
               trimmed[trimmed.index(after: dot)] == " " {
                let text = String(trimmed[trimmed.index(dot, offsetBy: 2)...])
                return ("\(number).", text, depth)
            }
        }
        return nil
    }

    private static func standaloneImage(_ line: String) -> (destination: String, alt: String)? {
        guard line.hasPrefix("!["), let closing = line.range(of: "]("), line.hasSuffix(")") else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<closing.lowerBound])
        let destination = String(line[closing.upperBound..<line.index(before: line.endIndex)])
        guard !destination.isEmpty else { return nil }
        return (destination, alt)
    }
}
