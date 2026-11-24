// MarkdownBlocks

import Foundation

/// 块级解析结果（纯数据，便于单测）。
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case listItem(marker: String, text: String, depth: Int)
    case quote(String)
    case code(String)
    case table(header: [String], rows: [[String]])
    case image(destination: String, alt: String)
    case divider
}

public enum MarkdownBlockParser {
    /// 按行解析成块。**只做行级判断**，不做完整语法树——
    /// 这是滑动性能的关键（会话里几十条消息，每条都要在滚动中反复求值）。
    public static func blocks(from raw: String) -> [MarkdownBlock] {
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

