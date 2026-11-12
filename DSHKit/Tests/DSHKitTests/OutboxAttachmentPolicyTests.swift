import XCTest
@testable import DSHKit

final class OutboxAttachmentPolicyTests: XCTestCase {
    func testHoldsNormalMessage() {
        XCTAssertTrue(OutboxAttachmentPolicy.canHold(imageCount: 3, totalBytes: 6_000_000))
    }

    func testRejectsEmpty() {
        XCTAssertFalse(OutboxAttachmentPolicy.canHold(imageCount: 0, totalBytes: 0))
    }

    func testRejectsTooManyImages() {
        XCTAssertFalse(OutboxAttachmentPolicy.canHold(imageCount: 10, totalBytes: 1_000))
    }

    func testAcceptsExactlyNine() {
        XCTAssertTrue(OutboxAttachmentPolicy.canHold(imageCount: 9, totalBytes: 9_000_000))
    }

    func testRejectsOversizeSingleMessage() {
        let tooBig = OutboxAttachmentPolicy.maxTotalBytes + 1
        XCTAssertFalse(OutboxAttachmentPolicy.canHold(imageCount: 1, totalBytes: tooBig))
    }

    func testBudgetShrinks() {
        let half = OutboxAttachmentPolicy.maxTotalBytes / 2
        XCTAssertTrue(OutboxAttachmentPolicy.fits(currentTotalBytes: half, adding: half))
        XCTAssertFalse(OutboxAttachmentPolicy.fits(currentTotalBytes: half, adding: half + 1))
    }
}
