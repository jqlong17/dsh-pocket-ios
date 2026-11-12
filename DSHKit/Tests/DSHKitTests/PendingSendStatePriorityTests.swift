import XCTest
@testable import DSHKit

final class PendingSendStatePriorityTests: XCTestCase {
    func testFailedWinsOverEverything() {
        // 失败必须让用户看见：即使同时存在 acked/queued 残留。
        XCTAssertEqual(PendingSendStatePriority.resolve(failed: true, acked: true, queued: true), .failed)
    }

    func testAckedWinsOverStaleQueuedMarker() {
        // 服务端已受理，不能因为断网标记残留就显示「现在断网」。
        XCTAssertEqual(PendingSendStatePriority.resolve(failed: false, acked: true, queued: true), .acked)
    }

    func testQueuedWhenOnlyQueued() {
        XCTAssertEqual(PendingSendStatePriority.resolve(failed: false, acked: false, queued: true), .queued)
    }

    func testSendingWhenNothingMarked() {
        XCTAssertEqual(PendingSendStatePriority.resolve(failed: false, acked: false, queued: false), .sending)
    }
}
