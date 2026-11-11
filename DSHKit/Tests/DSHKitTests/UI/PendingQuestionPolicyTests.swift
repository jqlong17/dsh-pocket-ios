import XCTest
@testable import DSHKit

final class PendingQuestionPolicyTests: XCTestCase {
    func testWaitingQuestionShows() {
        XCTAssertTrue(PendingQuestionPolicy.shouldShow(hasResult: false, turnEnded: false))
    }

    func testAnsweredOnMacDoesNotShow() {
        XCTAssertFalse(PendingQuestionPolicy.shouldShow(hasResult: true, turnEnded: false))
    }

    func testEndedTurnDoesNotShow() {
        XCTAssertFalse(PendingQuestionPolicy.shouldShow(hasResult: false, turnEnded: true))
    }
}
