import XCTest
@testable import DSHKit

final class ConversationOpenPlanTests: XCTestCase {
    func testCachedConversationSkipsLoading() {
        let plan = ConversationOpenPlan.make(cachedMessageCount: 36)
        XCTAssertTrue(plan.skipLoadingState)
        XCTAssertEqual(plan.loadSource, "cache")
    }

    func testEmptyConversationShowsLoading() {
        let plan = ConversationOpenPlan.make(cachedMessageCount: 0)
        XCTAssertFalse(plan.skipLoadingState)
        XCTAssertNil(plan.loadSource)
    }

    func testSingleCachedMessageIsEnough() {
        XCTAssertTrue(ConversationOpenPlan.make(cachedMessageCount: 1).skipLoadingState)
    }
}
