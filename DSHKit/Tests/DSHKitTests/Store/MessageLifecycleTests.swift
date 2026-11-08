import XCTest
@testable import DSHKit

final class MessageLifecycleTests: XCTestCase {
    // M01/M02/M03
    func testStateMachineHappyPath() {
        var lifecycle = MessageLifecycle()
        XCTAssertEqual(lifecycle.begin(rpcId: "r1", mode: .queue), .sending)
        XCTAssertEqual(lifecycle.state(for: "r1"), .sending)
        XCTAssertEqual(lifecycle.acknowledge(rpcId: "r1"), .accepted(.queue))
        XCTAssertEqual(lifecycle.state(for: "r1"), .accepted(.queue))
        XCTAssertEqual(lifecycle.commit(rpcId: "r1"), .committed)
        XCTAssertEqual(lifecycle.state(for: "r1"), .committed)
    }

    // M02：steer 模式被记录
    func testAcknowledgeKeepsSteerMode() {
        var lifecycle = MessageLifecycle()
        lifecycle.begin(rpcId: "r2", mode: .steer)
        XCTAssertEqual(lifecycle.acknowledge(rpcId: "r2"), .accepted(.steer))
        XCTAssertEqual(lifecycle.mode(for: "r2"), .steer)
    }

    // M04/M05：失败与重发
    func testFailureAndRetry() {
        var lifecycle = MessageLifecycle()
        lifecycle.begin(rpcId: "r3", mode: .queue)
        XCTAssertEqual(lifecycle.fail(rpcId: "r3"), .failed)
        XCTAssertEqual(lifecycle.failedRpcIds(), ["r3"])
        // 重发 = 旧 rpcId 移除，新 rpcId 重新开始
        lifecycle.commit(rpcId: "r3")
        lifecycle.begin(rpcId: "r4", mode: .queue)
        XCTAssertEqual(lifecycle.state(for: "r4"), .sending)
    }

    // M06：取消（从状态机消除）
    func testCancelCustomState() {
        var lifecycle = MessageLifecycle()
        lifecycle.begin(rpcId: "r5", mode: .steer)
        lifecycle.commit(rpcId: "r5")
        XCTAssertNil(lifecycle.failedRpcIds().first { $0 == "r5" })
    }

    func testAcknowledgeUnknownFails() {
        var lifecycle = MessageLifecycle()
        XCTAssertEqual(lifecycle.acknowledge(rpcId: "unknown"), .failed)
    }

    func testAcceptedAndFailedSets() {
        var lifecycle = MessageLifecycle()
        lifecycle.begin(rpcId: "a", mode: .queue)
        lifecycle.begin(rpcId: "b", mode: .steer)
        lifecycle.acknowledge(rpcId: "a")
        lifecycle.fail(rpcId: "b")
        XCTAssertEqual(lifecycle.acceptedRpcIds(), ["a"])
        XCTAssertEqual(lifecycle.failedRpcIds(), ["b"])
        XCTAssertNil(lifecycle.state(for: "missing"))
    }

    // M40/M41：steer/queue 选择
    func testSendModeDecider() {
        XCTAssertEqual(SendModeDecider.mode(isTurnRunning: true), .steer)
        XCTAssertEqual(SendModeDecider.mode(isTurnRunning: false), .queue)
    }
}
