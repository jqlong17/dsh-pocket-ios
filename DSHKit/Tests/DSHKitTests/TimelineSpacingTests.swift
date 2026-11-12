import XCTest
@testable import DSHKit

final class TimelineSpacingTests: XCTestCase {
    func testSameSpeakerIsTight() {
        XCTAssertEqual(TimelineSpacing.between(previousIsGroup: false, currentIsGroup: false,
                                               previousIsUser: true, currentIsUser: true), 8)
    }

    func testSpeakerChangeIsLoose() {
        XCTAssertEqual(TimelineSpacing.between(previousIsGroup: false, currentIsGroup: false,
                                               previousIsUser: true, currentIsUser: false), 18)
    }

    func testProcessRowsUseGroupSpacing() {
        XCTAssertEqual(TimelineSpacing.between(previousIsGroup: true, currentIsGroup: false,
                                               previousIsUser: nil, currentIsUser: true), 10)
        XCTAssertEqual(TimelineSpacing.between(previousIsGroup: false, currentIsGroup: false,
                                               previousIsUser: nil, currentIsUser: nil), 10)
    }
}

final class UnreadCounterTests: XCTestCase {
    private let list: [(isUser: Bool, isPending: Bool, sequence: Int)] = [
        (true, false, 1),   // 用户消息不算
        (false, false, 2),  // 助手回复，算
        (false, true, 3),   // 待发不算
        (false, false, 4),  // 助手回复，算
        (false, false, 1),  // 早于 mark
    ]

    func testCountsOnlyAssistantRepliesAfterMark() {
        XCTAssertEqual(UnreadCounter.replies(after: 1, messages: list), 2)
    }

    func testZeroWhenMarkIsLatest() {
        XCTAssertEqual(UnreadCounter.replies(after: 4, messages: list), 0)
    }

    func testEmptyList() {
        XCTAssertEqual(UnreadCounter.replies(after: 0, messages: []), 0)
    }
}
