import XCTest
@testable import DSHKit

final class SessionListFailurePolicyTests: XCTestCase {
    private func action(isCancelled: Bool = false,
                        isUnauthorized: Bool = false,
                        isStaleTunnel: Bool = false,
                        isTransient: Bool = false,
                        isSilent: Bool = false,
                        hasExistingSessions: Bool = false) -> SessionListFailureAction {
        SessionListFailurePolicy.action(isCancelled: isCancelled,
                                        isUnauthorized: isUnauthorized,
                                        isStaleTunnel: isStaleTunnel,
                                        isTransient: isTransient,
                                        isSilent: isSilent,
                                        hasExistingSessions: hasExistingSessions,
                                        message: "失败")
    }

    func testCancelledIsIgnored() {
        XCTAssertEqual(action(isCancelled: true, isUnauthorized: true), .ignore)
    }

    func testUnauthorizedGoesBackToConnect() {
        XCTAssertEqual(action(isUnauthorized: true), .reauthenticate)
    }

    func testStaleTunnelShowsAddressErrorNotRetry() {
        // 隧道地址过期时一直重试只会永远"正在重试"。
        XCTAssertEqual(action(isStaleTunnel: true, isTransient: true), .showAddressError)
    }

    func testTransientWithExistingListStaysQuiet() {
        XCTAssertEqual(action(isTransient: true, hasExistingSessions: true), .retryQuietly)
    }

    func testSilentRefreshStaysQuiet() {
        XCTAssertEqual(action(isTransient: true, isSilent: true), .retryQuietly)
    }

    func testTransientWithEmptyListShowsMessage() {
        XCTAssertEqual(action(isTransient: true, hasExistingSessions: false), .showMessage("失败"))
    }

    func testNonTransientShowsMessage() {
        XCTAssertEqual(action(isTransient: false, hasExistingSessions: true), .showMessage("失败"))
    }
}
