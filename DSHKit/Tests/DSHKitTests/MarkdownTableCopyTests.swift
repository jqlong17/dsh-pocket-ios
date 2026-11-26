import XCTest
@testable import DSHKit

final class MarkdownTableCopyTests: XCTestCase {
    private let header = ["名字", "地址", "备注"]
    private let rows = [["Mac", "10.56.166.90", "局域网"], ["阿里云", "ts.net:8443", "公网"]]

    func testTSVKeepsColumnsAligned() {
        let text = MarkdownTableCopy.tsv(header: header, rows: rows)
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[1].split(separator: "\t").count, 3)
        XCTAssertTrue(text.hasPrefix("名字\t地址\t备注"))
    }

    func testTSVEscapesTabsAndNewlinesInsideCells() {
        let text = MarkdownTableCopy.tsv(header: ["a\tb"], rows: [["x\ny"]])
        XCTAssertEqual(text, "a b\nx y")
    }

    func testMarkdownRoundTripsShape() {
        let text = MarkdownTableCopy.markdown(header: header, rows: rows)
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 4)                    // 表头 + 分隔 + 两行数据
        XCTAssertTrue(lines[0].hasPrefix("| 名字 |"))
        XCTAssertTrue(lines[1].contains("---"))
    }

    func testMarkdownPadsShortRowsAndEscapesPipes() {
        let text = MarkdownTableCopy.markdown(header: ["a", "b"], rows: [["x|y"]])
        XCTAssertTrue(text.contains("| x\\|y |  |"))
    }
}
