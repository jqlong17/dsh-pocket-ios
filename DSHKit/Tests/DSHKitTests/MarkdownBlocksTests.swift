import XCTest
@testable import DSHKit

final class MarkdownBlocksTests: XCTestCase {
    /// 回归：用户发了一个邮箱，气泡渲染成空白（2026-11-24 真机截图反馈）。
    func testEmailLineSurvivesAsParagraph() {
        let blocks = MarkdownBlockParser.blocks(from: "seskkk@outlook.com")
        XCTAssertEqual(blocks.count, 1, "邮箱这一行应产出 1 个块，实际: \(blocks)")
        guard case .paragraph(let text) = blocks[0] else {
            return XCTFail("应解析为段落，实际: \(blocks[0])")
        }
        XCTAssertEqual(text, "seskkk@outlook.com")
    }

    func testPlainSentenceIsParagraph() {
        let blocks = MarkdownBlockParser.blocks(from: "你直接修改代码吧")
        XCTAssertEqual(blocks, [.paragraph("你直接修改代码吧")])
    }

    func testHeadingAndBullet() {
        let blocks = MarkdownBlockParser.blocks(from: "# 标题\n- 条目")
        XCTAssertEqual(blocks, [.heading(level: 1, text: "标题"), .listItem(marker: "•", text: "条目", depth: 0)])
    }

    func testCodeFenceKeepsContent() {
        let blocks = MarkdownBlockParser.blocks(from: "```\nlet a = 1\n```")
        XCTAssertEqual(blocks, [.code("let a = 1")])
    }

    func testTable() {
        let blocks = MarkdownBlockParser.blocks(from: "| a | b |\n| --- | --- |\n| 1 | 2 |")
        guard case .table(let header, let rows) = blocks.first else { return XCTFail("应解析为表格: \(blocks)") }
        XCTAssertEqual(header, ["a", "b"])
        XCTAssertEqual(rows, [["1", "2"]])
    }

    func testOrderedList() {
        XCTAssertEqual(MarkdownBlockParser.blocks(from: "1. 第一步"), [.listItem(marker: "1.", text: "第一步", depth: 0)])
    }

    func testDotInsideWordIsNotList() {
        // "outlook.com" 里的点不能被当成有序列表标记
        XCTAssertEqual(MarkdownBlockParser.blocks(from: "v1.2 发布"), [.paragraph("v1.2 发布")])
    }
}
