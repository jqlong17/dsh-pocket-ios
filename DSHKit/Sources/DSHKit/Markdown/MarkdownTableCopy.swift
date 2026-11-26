// MarkdownTableCopy
//
// 表格的两种复制形态（2026-11-26 用户反馈：表格内容选不中也复制不了）。
//
// 为什么单独做序列化：SwiftUI 的 `.textSelection(.enabled)` 只让每个 Text 各自可选，
// 表格是多行多列拼出来的，选不出「整张表」。所以除了让单元格可选，再给一个明确的
// 「复制整张表」出口：制表符版可直接粘进 Excel/飞书，Markdown 版可贴回文档。

import Foundation

public enum MarkdownTableCopy {
    /// 制表符分隔（TSV）：粘进 Excel / Numbers / 飞书表格会自动分列。
    public static func tsv(header: [String], rows: [[String]]) -> String {
        ([header] + rows).map { line in
            line.map(escapeTSV).joined(separator: "\t")
        }.joined(separator: "\n")
    }

    /// Markdown 源码：贴回 Markdown 文档仍是表格。
    public static func markdown(header: [String], rows: [[String]]) -> String {
        let columnCount = max(header.count, rows.map(\.count).max() ?? 0)
        func padded(_ cells: [String]) -> [String] {
            cells + Array(repeating: "", count: max(0, columnCount - cells.count))
        }
        var lines: [String] = []
        lines.append("| " + padded(header).map(escapePipe).joined(separator: " | ") + " |")
        lines.append("|" + Array(repeating: " --- |", count: columnCount).joined())
        for row in rows {
            lines.append("| " + padded(row).map(escapePipe).joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    // 单元格内的制表符/换行会破坏 TSV 的列与行结构，换成空格。
    private static func escapeTSV(_ cell: String) -> String {
        cell.replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func escapePipe(_ cell: String) -> String {
        cell.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
