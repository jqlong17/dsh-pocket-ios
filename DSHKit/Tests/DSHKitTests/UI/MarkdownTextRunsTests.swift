import XCTest
@testable import DSHKit

final class MarkdownTextRunsTests: XCTestCase {
    func testConsecutiveTextBlocksMergeIntoOneRun() {
        let blocks: [MarkdownBlock] = [
            .paragraph("第一段"),
            .heading(level: 3, text: "小标题"),
            .listItem(marker: "•", text: "条目", depth: 0),
            .quote("引用"),
        ]
        XCTAssertEqual(MarkdownTextRuns.group(blocks), [.text(blocks)])
    }

    func testCodeTableImageAndDividerBreakRuns() {
        let paragraphA = MarkdownBlock.paragraph("前")
        let code = MarkdownBlock.code("let a = 1")
        let table = MarkdownBlock.table(header: ["a"], rows: [["1"]])
        let image = MarkdownBlock.image(destination: "https://x/y.png", alt: "图")
        let divider = MarkdownBlock.divider
        let paragraphB = MarkdownBlock.paragraph("后")

        XCTAssertEqual(
            MarkdownTextRuns.group([paragraphA, code, table, image, divider, paragraphB]),
            [
                .text([paragraphA]),
                .block(code),
                .block(table),
                .block(image),
                .block(divider),
                .text([paragraphB]),
            ]
        )
    }

    func testTwoTextBlocksAroundCodeStaySeparate() {
        // 关键：代码块前后两段文本不能合并，否则代码会丢失底色/横向滚动。
        let first = MarkdownBlock.paragraph("说明")
        let code = MarkdownBlock.code("print(1)")
        let second = MarkdownBlock.paragraph("继续说明")
        XCTAssertEqual(
            MarkdownTextRuns.group([first, code, second]),
            [.text([first]), .block(code), .text([second])]
        )
    }

    func testEmptyInputProducesNoRuns() {
        let none: [MarkdownTextRun] = []
        XCTAssertEqual(MarkdownTextRuns.group([]), none)
    }

    func testSeparatorKeepsConsecutiveListItemsTight() {
        let item = MarkdownBlock.listItem(marker: "•", text: "x", depth: 0)
        XCTAssertEqual(MarkdownTextRuns.separator(previous: item, current: item), "\n")
    }

    func testSeparatorAfterHeadingIsSingleNewline() {
        let heading = MarkdownBlock.heading(level: 2, text: "标题")
        let paragraph = MarkdownBlock.paragraph("正文")
        XCTAssertEqual(MarkdownTextRuns.separator(previous: heading, current: paragraph), "\n")
    }

    func testSeparatorKeepsConsecutiveQuoteLinesTogether() {
        XCTAssertEqual(MarkdownTextRuns.separator(previous: .quote("第一行"), current: .quote("第二行")), "\n")
    }

    func testSeparatorElsewhereIsBlankLine() {
        XCTAssertEqual(MarkdownTextRuns.separator(previous: .paragraph("a"), current: .paragraph("b")), "\n\n")
        XCTAssertEqual(MarkdownTextRuns.separator(previous: nil, current: .paragraph("a")), "")
        XCTAssertEqual(MarkdownTextRuns.separator(previous: .quote("q"), current: .paragraph("b")), "\n\n")
    }
}
