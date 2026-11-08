import XCTest
@testable import DSHKit

final class LoginTests: XCTestCase {
    // P10
    func testLoginSuccess() {
        let outcome = LoginClassifier.outcome(statusCode: 302, redirected: true, hasPocketCookie: true)
        XCTAssertEqual(outcome, .success)
    }

    // P11
    func testWrongPINReturnsLoginPage() {
        let outcome = LoginClassifier.outcome(statusCode: 200, redirected: false, hasPocketCookie: false)
        XCTAssertEqual(outcome, .invalidPIN)
    }

    // P12
    func testRateLimited() {
        let outcome = LoginClassifier.outcome(statusCode: 429, redirected: false, hasPocketCookie: false)
        XCTAssertEqual(outcome, .rateLimited)
    }

    // P13
    func testUnauthorizedStatusMapsToError() {
        XCTAssertEqual(DSHError.from(status: 401), .unauthorized)
        XCTAssertEqual(DSHError.from(status: 429), .rateLimited)
        XCTAssertNil(DSHError.from(status: 200))
        XCTAssertEqual(DSHError.from(status: 500), .server(status: 500, message: nil))
    }
}
