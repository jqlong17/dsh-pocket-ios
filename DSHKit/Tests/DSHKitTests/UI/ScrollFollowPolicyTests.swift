import XCTest
import CoreGraphics
@testable import DSHKit

final class ScrollFollowPolicyTests: XCTestCase {
    func testAtBottomOnlyWithinEightPoints() {
        XCTAssertTrue(ScrollFollowPolicy.isAtBottom(distanceFromBottom: 0))
        XCTAssertTrue(ScrollFollowPolicy.isAtBottom(distanceFromBottom: 8))
        XCTAssertFalse(ScrollFollowPolicy.isAtBottom(distanceFromBottom: 8.5))
        XCTAssertFalse(ScrollFollowPolicy.isAtBottom(distanceFromBottom: 48))
    }

    func testBottomRestoresFollow() {
        XCTAssertEqual(
            ScrollFollowPolicy.action(distanceFromBottom: 2, isDragging: true, followsLatest: false),
            .follow
        )
    }

    func testLeavingBottomStopsFollow() {
        XCTAssertEqual(
            ScrollFollowPolicy.action(distanceFromBottom: 30, isDragging: true, followsLatest: true),
            .stopFollow
        )
    }

    func testGrowthPinsOnlyWhileFollowing() {
        XCTAssertEqual(
            ScrollFollowPolicy.action(distanceFromBottom: 30, isDragging: false, followsLatest: true),
            .pinToBottom
        )
        XCTAssertEqual(
            ScrollFollowPolicy.action(distanceFromBottom: 30, isDragging: false, followsLatest: false),
            .keep
        )
    }

    func testAutoScrollForbiddenWhileDraggingEvenIfForced() {
        XCTAssertFalse(ScrollFollowPolicy.canAutoScroll(isDragging: true, followsLatest: true, force: true))
        XCTAssertFalse(ScrollFollowPolicy.canAutoScroll(isDragging: true, followsLatest: false, force: false))
    }

    func testAutoScrollAllowedWhenFollowingOrForced() {
        XCTAssertTrue(ScrollFollowPolicy.canAutoScroll(isDragging: false, followsLatest: true, force: false))
        XCTAssertTrue(ScrollFollowPolicy.canAutoScroll(isDragging: false, followsLatest: false, force: true))
        XCTAssertFalse(ScrollFollowPolicy.canAutoScroll(isDragging: false, followsLatest: false, force: false))
    }
}
