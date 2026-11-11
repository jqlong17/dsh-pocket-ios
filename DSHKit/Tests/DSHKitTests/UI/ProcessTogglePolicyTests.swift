import XCTest
@testable import DSHKit

final class ProcessTogglePolicyTests: XCTestCase {
    func testOpeningDoesNotScrollRowToTop() {
        let plan = ProcessTogglePlan.make(isExpanded: false, needsDetails: true)
        XCTAssertTrue(plan.opening)
        XCTAssertTrue(plan.loadDetails)
        XCTAssertFalse(plan.dropDetails)
        XCTAssertFalse(plan.followLatest)
        XCTAssertGreaterThan(plan.suppressAutoScroll, 0)
        XCTAssertFalse(plan.scrollToRowTop)
    }

    func testOpeningSkipsFetchWhenDetailsAlreadyLoaded() {
        let plan = ProcessTogglePlan.make(isExpanded: false, needsDetails: false)
        XCTAssertTrue(plan.opening)
        XCTAssertFalse(plan.loadDetails)
        XCTAssertFalse(plan.scrollToRowTop)
    }

    func testClosingDropsDetailsAndDoesNotScroll() {
        let plan = ProcessTogglePlan.make(isExpanded: true, needsDetails: false)
        XCTAssertFalse(plan.opening)
        XCTAssertFalse(plan.loadDetails)
        XCTAssertTrue(plan.dropDetails)
        XCTAssertFalse(plan.followLatest)
        XCTAssertFalse(plan.scrollToRowTop)
    }
}
