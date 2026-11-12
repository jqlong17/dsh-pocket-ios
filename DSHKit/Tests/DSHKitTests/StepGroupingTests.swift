import XCTest
@testable import DSHKit

final class StepGroupingTests: XCTestCase {
    private func step(_ turn: Int, _ sequence: Int) -> StepGrouping.Step {
        .init(turn: turn, sequence: sequence)
    }

    func testSingleTurnSingleGroup() {
        let steps = [step(1, 1), step(1, 2), step(1, 3)]
        XCTAssertEqual(StepGrouping.groups(steps: steps, textBoundaries: []), [[0, 1, 2]])
    }

    func testTurnChangeSplitsGroups() {
        let steps = [step(1, 1), step(1, 2), step(2, 3)]
        XCTAssertEqual(StepGrouping.groups(steps: steps, textBoundaries: []), [[0, 1], [2]])
    }

    func testAssistantTextSplitsGroups() {
        // 干活 → 说话（seq 2）→ 再干活：应分成两组，否则会挤成一条超长过程行。
        let steps = [step(1, 1), step(1, 3), step(1, 5)]
        XCTAssertEqual(StepGrouping.groups(steps: steps, textBoundaries: [2]), [[0], [1, 2]])
    }

    func testUnsortedInputIsSortedBySequence() {
        let steps = [step(1, 5), step(1, 1), step(1, 3)]
        XCTAssertEqual(StepGrouping.groups(steps: steps, textBoundaries: []), [[1, 2, 0]])
    }

    func testEmptyInput() {
        XCTAssertTrue(StepGrouping.groups(steps: [], textBoundaries: [1, 2]).isEmpty)
    }
}
