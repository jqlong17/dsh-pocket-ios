import XCTest
@testable import DSHKit

final class LoginExtraTests: XCTestCase {
    func testRedirectWithoutCookieIsServerError() {
        let outcome = LoginClassifier.outcome(statusCode: 302, redirected: true, hasPocketCookie: false)
        XCTAssertEqual(outcome, .serverError(status: 302))
    }

    func testRedirectNotDetectedButCookiePresentOn200IsInvalidPIN() {
        let outcome = LoginClassifier.outcome(statusCode: 200, redirected: false, hasPocketCookie: true)
        XCTAssertEqual(outcome, .invalidPIN)
    }

    func testForbiddenIsInvalidPIN() {
        XCTAssertEqual(LoginClassifier.outcome(statusCode: 403, redirected: false, hasPocketCookie: false), .invalidPIN)
        XCTAssertEqual(LoginClassifier.outcome(statusCode: 500, redirected: false, hasPocketCookie: false), .serverError(status: 500))
    }
}
