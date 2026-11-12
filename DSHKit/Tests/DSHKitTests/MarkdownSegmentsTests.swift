import XCTest
@testable import DSHKit

final class MarkdownSegmentsTests: XCTestCase {
    private let base = URL(string: "https://example.com")!

    func testPlainTextStaysOneSegment() {
        let segments = MarkdownSegments.split("只有文字") { _ in nil }
        XCTAssertEqual(segments, [.text("只有文字")])
    }

    func testStandaloneImageSplitsOut() {
        let md = "前文\n![截图](a.png)\n后文"
        let segments = MarkdownSegments.split(md) { dest in
            dest == "a.png" ? self.base.appendingPathComponent("a.png") : nil
        }
        guard case .text(let first) = segments[0],
              case .image(let url, let caption) = segments[1],
              case .text(let last) = segments[2] else {
            return XCTFail("分段不符：\(segments)")
        }
        XCTAssertEqual(first, "前文")
        XCTAssertEqual(url.lastPathComponent, "a.png")
        XCTAssertEqual(caption, "截图")
        XCTAssertEqual(last, "后文")
    }

    func testInlineImageStaysText() {
        let segments = MarkdownSegments.split("见 ![图](a.png) 这里") { _ in self.base }
        XCTAssertEqual(segments.count, 1)
    }

    func testUnresolvableImageStaysText() {
        let segments = MarkdownSegments.split("![图](a.png)") { _ in nil }
        XCTAssertEqual(segments, [.text("![图](a.png)")])
    }

    func testEmptyCaptionBecomesNil() {
        let segments = MarkdownSegments.split("![](a.png)") { _ in self.base }
        guard case .image(_, let caption) = segments.first else { return XCTFail("应为图片段") }
        XCTAssertNil(caption)
    }
}
