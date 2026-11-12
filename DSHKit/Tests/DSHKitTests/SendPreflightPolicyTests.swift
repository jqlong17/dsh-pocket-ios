import XCTest
@testable import DSHKit

final class SendPreflightPolicyTests: XCTestCase {
    func testUnknownStateMustSend() {
        // App 冷启动头几秒 NWPathMonitor 还没有状态；这时的消息必须照常发，
        // 否则用户会看到「现在断网」但网络其实是好的。
        XCTAssertEqual(SendPreflightPolicy.action(isReachable: nil), .send)
    }

    func testReachableSends() {
        XCTAssertEqual(SendPreflightPolicy.action(isReachable: true), .send)
    }

    func testUnreachableHoldsOffline() {
        // 已知不可达：跳过 3 次重试直接写入暂存（用户实测原本要等 18 秒）。
        XCTAssertEqual(SendPreflightPolicy.action(isReachable: false), .holdOffline)
    }
}
