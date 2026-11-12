import XCTest
@testable import DSHKit

final class PromptPolicyTests: XCTestCase {
    func testLiveSteersWhileRunning() {
        // 生成中发的消息必须打断当前轮；排队会让电脑端显示「排队」，用户以为卡住。
        XCTAssertEqual(PromptPolicy.liveMode(isRunning: true), .steer)
    }

    func testLiveQueuesWhenIdle() {
        XCTAssertEqual(PromptPolicy.liveMode(isRunning: false), .queue)
    }

    func testReplyNeverSteers() {
        XCTAssertEqual(PromptPolicy.replyMode(isRunning: true), .queue)
        XCTAssertEqual(PromptPolicy.replyMode(isRunning: false), .queue)
    }

    func testBacklogAlwaysQueues() {
        XCTAssertEqual(PromptPolicy.backlogMode, .queue)
    }
}
