import XCTest
@testable import DSHKit

final class PageTests: XCTestCase {
    // P40
    func testPageDecodingKeepsOrderAndHasMore() throws {
        let json = try fixtureJSON("session_page")
        let page = DSHDecoding.page(fromValue: json)

        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.records.count, 10)

        // 顺序保持：第 1 条标题、第 2 条用户消息、最后一条 unknown。
        if case .title(let seq, _) = page.records[0] { XCTAssertEqual(seq, 1) } else { XCTFail("expected title first") }
        if case .message(let message) = page.records[1] {
            XCTAssertEqual(message.sequence, 2)
        } else {
            XCTFail("expected message second")
        }
        if case .unknown = page.records[9] { } else { XCTFail("expected unknown last") }
    }

    func testEmptyPageDecoding() {
        let page = DSHDecoding.page(fromValue: [:])
        XCTAssertTrue(page.records.isEmpty)
        XCTAssertFalse(page.hasMore)
    }
}
