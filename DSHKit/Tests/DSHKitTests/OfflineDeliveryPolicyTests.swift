import XCTest
@testable import DSHKit

final class OfflineDeliveryPolicyTests: XCTestCase {
    func testBacklogAlwaysQueues() {
        XCTAssertEqual(OfflineDeliveryPolicy.deliveryMode, "queue")
    }

    func testShortDelayNotAnnotated() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(OfflineDeliveryPolicy.shouldAnnotate(createdAt: now.addingTimeInterval(-60), now: now))
    }

    func testLongDelayAnnotatedWithClockTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let sent = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 1, minute: 5))!
        let now = sent.addingTimeInterval(31 * 60)
        XCTAssertTrue(OfflineDeliveryPolicy.shouldAnnotate(createdAt: sent, now: now))
        let text = OfflineDeliveryPolicy.annotatedText("在吗", createdAt: sent, now: now, calendar: calendar)
        XCTAssertEqual(text, "（离线期间 01:05 发出）\n在吗")
    }

    func testAnnotationKeepsOriginalTextIntact() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let text = OfflineDeliveryPolicy.annotatedText("原文", createdAt: now.addingTimeInterval(-10), now: now)
        XCTAssertEqual(text, "原文")
    }

    func testInterMessageDelayIsShortButNonZero() {
        XCTAssertGreaterThan(OfflineDeliveryPolicy.interMessageDelay, .zero)
        XCTAssertLessThanOrEqual(OfflineDeliveryPolicy.interMessageDelay, .milliseconds(500))
    }
}
