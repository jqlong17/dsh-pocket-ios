import XCTest
@testable import DSHKit

final class SendRetryPolicyTests: XCTestCase {
    private func should(heldOffline: Bool = false,
                        sendFailed: Bool = false,
                        accepted: Bool = false,
                        autoRetried: Bool = false) -> Bool {
        SendRetryPolicy.shouldAutoResend(heldOffline: heldOffline, sendFailed: sendFailed,
                                         accepted: accepted, autoRetried: autoRetried)
    }

    func testHeldOfflineAlwaysResends() {
        XCTAssertTrue(should(heldOffline: true))
        XCTAssertTrue(should(heldOffline: true, autoRetried: true))
    }

    func testFailedResendsOnce() {
        XCTAssertTrue(should(sendFailed: true))
    }

    func testFailedDoesNotResendAfterAutoRetry() {
        // 永久失败的消息不能每轮连接都重试一次。
        XCTAssertFalse(should(sendFailed: true, autoRetried: true))
    }

    func testAcceptedNeverResends() {
        XCTAssertFalse(should(accepted: true))
        XCTAssertFalse(should(sendFailed: true, accepted: true))
        XCTAssertFalse(should(heldOffline: true, accepted: true))
    }

    func testNothingToDoWhenClean() {
        XCTAssertFalse(should())
    }
}
