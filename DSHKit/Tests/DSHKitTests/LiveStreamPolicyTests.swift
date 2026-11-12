import XCTest
@testable import DSHKit

final class LiveStreamPolicyTests: XCTestCase {
    func testBackoffDoublesAndCaps() {
        XCTAssertEqual(LiveStreamPolicy.nextReconnectDelay(after: .seconds(1)), .seconds(2))
        XCTAssertEqual(LiveStreamPolicy.nextReconnectDelay(after: .seconds(8)), .seconds(16))
        XCTAssertEqual(LiveStreamPolicy.nextReconnectDelay(after: .seconds(16)), .seconds(20))
        XCTAssertEqual(LiveStreamPolicy.nextReconnectDelay(after: .seconds(20)), .seconds(20))
    }

    func testIdleReconnectOnlyWhileRunning() {
        XCTAssertTrue(LiveStreamPolicy.shouldReconnect(isRunning: true, idle: .seconds(25)))
        XCTAssertFalse(LiveStreamPolicy.shouldReconnect(isRunning: true, idle: .seconds(24)))
        // 空闲时长时间没帧是正常的，不能重连。
        XCTAssertFalse(LiveStreamPolicy.shouldReconnect(isRunning: false, idle: .seconds(120)))
    }

    func testHeartbeatShorterThanIdleTimeout() {
        XCTAssertLessThan(LiveStreamPolicy.heartbeatInterval, LiveStreamPolicy.runningIdleTimeout + .seconds(1))
    }

    func testPollBudgetIsSanelyShort() {
        let total = LiveStreamPolicy.historyPollInterval * LiveStreamPolicy.historyPollAttempts
        XCTAssertLessThanOrEqual(total, .seconds(30))
        XCTAssertGreaterThan(LiveStreamPolicy.historyPollAttempts, 0)
    }
}
