import XCTest
@testable import DSHKit

final class SessionCompletionTrackerTests: XCTestCase {
    func testFirstObservationDoesNotReportCompletion() {
        var tracker = SessionCompletionTracker()
        XCTAssertEqual(tracker.update(latest: ["a": false, "b": true]), [])
    }

    func testRunningToIdleReportsCompletion() {
        var tracker = SessionCompletionTracker(previous: ["a": true])
        XCTAssertEqual(tracker.update(latest: ["a": false]), ["a"])
    }

    func testIdleToIdleAndIdleToRunningAreNotCompletions() {
        var tracker = SessionCompletionTracker(previous: ["a": false, "b": false])
        XCTAssertEqual(tracker.update(latest: ["a": false, "b": true]), [])
        XCTAssertEqual(tracker.update(latest: ["a": true, "b": false]), ["b"])
    }

    func testSessionThatRunsAgainIsNotCompleted() {
        var tracker = SessionCompletionTracker(previous: ["a": true])
        XCTAssertEqual(tracker.update(latest: ["a": true]), [])
        XCTAssertEqual(tracker.running["a"], true)
    }
}
