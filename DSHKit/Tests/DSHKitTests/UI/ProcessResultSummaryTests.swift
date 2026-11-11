import XCTest
@testable import DSHKit

final class ProcessResultSummaryTests: XCTestCase {
    func testReadWrapperDoesNotShowTags() {
        let raw = """
        <path>/Users/ruska/projects/dsh-pocket-ios/DSHPocket/Session/ConnectionModel+Connect.swift</path>
        <type>file</type>
        <content>...
        """
        let text = ProcessResultSummary.display(tool: "read", raw: raw)
        XCTAssertFalse(text.contains("<"))
        XCTAssertEqual(text, "文件，正文已省略")
    }

    func testReadWrapperShowsContentNotPath() {
        let raw = """
        <path>/tmp/A.swift</path>
        <type>file</type>
        <content>
        import SwiftUI
        struct Pocket {}
        </content>
        """
        let text = ProcessResultSummary.display(tool: "read", raw: raw)
        XCTAssertTrue(text.hasPrefix("文件"))
        XCTAssertTrue(text.contains("import SwiftUI"))
        XCTAssertFalse(text.contains("/tmp/A.swift"))
    }

    func testSearchCount() {
        let raw = """
        /Users/ruska/projects/dsh-pocket-ios/DSHPocket
        Found 13 matches

        DSHPocket/Session/Demo.swift
        Line 59: func openDemo
        """
        let text = ProcessResultSummary.display(tool: "grep", raw: raw)
        XCTAssertTrue(text.hasPrefix("13 处匹配"))
        XCTAssertTrue(text.contains("Line 59"))
    }

    func testShortPath() {
        XCTAssertEqual(
            ProcessResultSummary.shortPath("/Users/ruska/projects/dsh-pocket-ios/DSHPocket/Session/A.swift"),
            "A.swift"
        )
    }
}
