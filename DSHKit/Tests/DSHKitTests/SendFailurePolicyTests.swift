import XCTest
@testable import DSHKit

final class SendFailurePolicyTests: XCTestCase {
    func testCancelWinsOverEverything() {
        // 用户取消优先级最高：即使同时是瞬时错误，也要退回输入框。
        XCTAssertEqual(SendFailurePolicy.action(isCancelled: true, isUnauthorized: true,
                                                isTransient: true, isStaleTunnel: false),
                       .returnToComposer)
    }

    func testUnauthorizedKeepsTextAndAsksRelogin() {
        XCTAssertEqual(SendFailurePolicy.action(isCancelled: false, isUnauthorized: true,
                                                isTransient: false, isStaleTunnel: false),
                       .reauthenticate)
    }

    func testTransientHoldsOffline() {
        XCTAssertEqual(SendFailurePolicy.action(isCancelled: false, isUnauthorized: false,
                                                isTransient: true, isStaleTunnel: false),
                       .holdOffline)
    }

    func testStaleTunnelIsNotHeldOffline() {
        // 地址过期时补发只会一直失败，应判失败让用户重新扫码。
        XCTAssertEqual(SendFailurePolicy.action(isCancelled: false, isUnauthorized: false,
                                                isTransient: true, isStaleTunnel: true),
                       .markFailed)
    }

    func testOtherErrorsMarkFailed() {
        XCTAssertEqual(SendFailurePolicy.action(isCancelled: false, isUnauthorized: false,
                                                isTransient: false, isStaleTunnel: false),
                       .markFailed)
    }
}
