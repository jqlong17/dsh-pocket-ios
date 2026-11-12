import XCTest
@testable import DSHKit

final class PromptPolicyTests: XCTestCase {
    func testLiveSteersOnlyWhenTurnEventsConfirmed() {
        XCTAssertEqual(PromptPolicy.liveMode(turnEventsSeen: true, isRunning: true), .steer)
    }

    func testLiveQueuesWhenTurnStateIsGuess() {
        // 没见过实时事件时，列表里的 running 不可信：排队比打断安全。
        XCTAssertEqual(PromptPolicy.liveMode(turnEventsSeen: false, isRunning: true), .queue)
    }

    func testLiveQueuesWhenIdle() {
        XCTAssertEqual(PromptPolicy.liveMode(turnEventsSeen: true, isRunning: false), .queue)
    }

    func testReplyNeverSteers() {
        XCTAssertEqual(PromptPolicy.replyMode(isRunning: true), .queue)
        XCTAssertEqual(PromptPolicy.replyMode(isRunning: false), .queue)
    }

    func testBacklogAlwaysQueues() {
        XCTAssertEqual(PromptPolicy.backlogMode, .queue)
    }
}
