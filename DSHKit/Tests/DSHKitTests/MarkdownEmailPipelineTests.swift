import XCTest
import Foundation
@testable import DSHKit

/// 复现「用户发邮箱 → 气泡空白」：逐段验证渲染链路的每一步。
final class MarkdownEmailPipelineTests: XCTestCase {
    private let email = "seskkk@outlook.com"

    func testSegmentsKeepEmail() {
        let segments = MarkdownSegments.split(email) { _ in nil }
        XCTAssertEqual(segments.count, 1, "分段后应只有 1 段，实际: \(segments)")
        if case .text(let text) = segments[0] {
            XCTAssertEqual(text.trimmingCharacters(in: .whitespacesAndNewlines), email)
        } else {
            XCTFail("应解析为文本段，实际: \(segments[0])")
        }
    }

    func testTruncationKeepsEmail() {
        let result = MarkdownTruncation.apply(to: email)
        XCTAssertFalse(result.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "截断后内容被清空：\(result)")
    }

    /// 关键怀疑点：Foundation 的 Markdown 解析把 `x@y.com` 当成链接/附件，字符可能丢失。
    func testAttributedStringKeepsCharacters() {
        let attributed = try? AttributedString(
            markdown: email,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        XCTAssertNotNil(attributed)
        XCTAssertEqual(String(attributed!.characters), email, "行内解析后字符丢失")
    }
}
