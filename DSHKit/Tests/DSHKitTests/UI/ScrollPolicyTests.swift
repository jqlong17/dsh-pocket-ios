import XCTest
@testable import DSHKit

final class ScrollPolicyTests: XCTestCase {
    // U01：在底部自动跟随
    func testAtBottomFollowsNewMessages() {
        var policy = ScrollPolicy(isAtBottom: true)
        XCTAssertEqual(policy.onNewMessages(delta: 1), .autoScroll)
        XCTAssertEqual(policy.unreadCount, 0)
    }

    // U02：不在底部不抢滚动，累计未读
    func testScrolledUpKeepsPositionAndCountsUnread() {
        var policy = ScrollPolicy(isAtBottom: true)
        policy.onScrollChanged(isAtBottom: false)
        XCTAssertEqual(policy.onNewMessages(delta: 2), .keepPosition)
        XCTAssertEqual(policy.unreadCount, 2)
        XCTAssertTrue(policy.showsBackToBottom)
    }

    // U03：回到底部清零
    func testBackToBottomResetsUnread() {
        var policy = ScrollPolicy(isAtBottom: false)
        _ = policy.onNewMessages(delta: 3)
        XCTAssertTrue(policy.requestBottom(force: true))
        XCTAssertEqual(policy.unreadCount, 0)
        XCTAssertFalse(policy.showsBackToBottom)
    }

    // U04：首屏稳定期自动跟随
    func testSettlingAutoFollows() {
        var policy = ScrollPolicy(isAtBottom: false)
        policy.beginSettling()
        XCTAssertEqual(policy.onNewMessages(delta: 1), .autoScroll)
        policy.endSettling()
        XCTAssertEqual(policy.onNewMessages(delta: 1), .keepPosition)
    }

    // U05：用户上滑使补滚失效（generation 递增）
    func testScrollInvalidatesPendingScrolls() {
        var policy = ScrollPolicy(isAtBottom: true)
        let before = policy.generation
        policy.onScrollChanged(isAtBottom: false)
        XCTAssertGreaterThan(policy.generation, before)
        XCTAssertFalse(policy.requestBottom(force: false))
    }

    func testZeroDeltaKeepsPosition() {
        var policy = ScrollPolicy(isAtBottom: true)
        XCTAssertEqual(policy.onNewMessages(delta: 0), .keepPosition)
    }
}
