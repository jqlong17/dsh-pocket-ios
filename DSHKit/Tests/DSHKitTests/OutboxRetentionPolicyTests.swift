import XCTest
@testable import DSHKit

final class OutboxRetentionPolicyTests: XCTestCase {
    func testServerConfirmedAllowsRemoval() {
        XCTAssertTrue(OutboxRetentionPolicy.canRemove(cause: .serverConfirmed))
    }

    func testUserCancelledAllowsRemovalBecauseTextReturnsToComposer() {
        XCTAssertTrue(OutboxRetentionPolicy.canRemove(cause: .userCancelled))
    }

    /// 用户点「删除」是明确的丢弃意图：允许删，但必须是**新的** cause，
    /// 不能沿用 `.sendFailed`（自动路径永远不删失败正文）。
    func testUserDiscardedAllowsRemoval() {
        XCTAssertTrue(OutboxRetentionPolicy.canRemove(cause: .userDiscarded))
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
