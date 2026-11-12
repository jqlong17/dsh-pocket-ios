import XCTest
@testable import DSHKit

final class OutboxRetentionPolicyTests: XCTestCase {
    func testServerConfirmedAllowsRemoval() {
        XCTAssertTrue(OutboxRetentionPolicy.canRemove(cause: .serverConfirmed))
    }

    func testUserCancelledAllowsRemovalBecauseTextReturnsToComposer() {
        XCTAssertTrue(OutboxRetentionPolicy.canRemove(cause: .userCancelled))
    }

    func testNetworkFailureKeepsText() {
        XCTAssertFalse(OutboxRetentionPolicy.canRemove(cause: .networkFailure))
    }

    func testSendFailureKeepsText() {
        XCTAssertFalse(OutboxRetentionPolicy.canRemove(cause: .sendFailed))
    }

    func testAuthExpiryKeepsText() {
        XCTAssertFalse(OutboxRetentionPolicy.canRemove(cause: .authExpired))
    }
}
