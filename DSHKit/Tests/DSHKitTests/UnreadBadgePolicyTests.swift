import XCTest
@testable import DSHKit

final class UnreadBadgePolicyTests: XCTestCase {
    func testHiddenUntilEnoughReplies() {
        XCTAssertFalse(UnreadBadgePolicy.shouldShowBadge(assistantReplies: 0))
        XCTAssertFalse(UnreadBadgePolicy.shouldShowBadge(assistantReplies: 4))
        XCTAssertTrue(UnreadBadgePolicy.shouldShowBadge(assistantReplies: 5))
        XCTAssertTrue(UnreadBadgePolicy.shouldShowBadge(assistantReplies: 12))
    }

    func testBadgeTextOmitsZero() {
        XCTAssertNil(UnreadBadgePolicy.badgeText(for: 0))
        XCTAssertEqual(UnreadBadgePolicy.badgeText(for: 1), "1")
        XCTAssertEqual(UnreadBadgePolicy.badgeText(for: 5), "5")
    }

    func testBadgeTextCapsAt99Plus() {
        XCTAssertEqual(UnreadBadgePolicy.badgeText(for: 99), "99")
        XCTAssertEqual(UnreadBadgePolicy.badgeText(for: 100), "99+")
        XCTAssertEqual(UnreadBadgePolicy.badgeText(for: 5000), "99+")
    }

    func testThresholdIsFiveReplies() {
        XCTAssertEqual(UnreadBadgePolicy.replyThreshold, 5)
    }
}
