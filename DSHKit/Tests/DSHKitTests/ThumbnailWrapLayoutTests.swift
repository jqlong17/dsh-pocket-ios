import XCTest
@testable import DSHKit

final class ThumbnailWrapLayoutTests: XCTestCase {
    func testFiveImagesOnIPhoneWrapToThreePlusTwo() {
        // iPhone 16 Pro 一屏：393 屏宽 - 32 padding - 44 气泡左侧最小留白 - 26 气泡内边距 = 291。
        let columns = ThumbnailWrapLayout.columnsPerRow(availableWidth: 291, itemSize: 88, spacing: 6)
        XCTAssertEqual(columns, 3)

        let rows = ThumbnailWrapLayout.rows(Array(0..<5), availableWidth: 291, itemSize: 88, spacing: 6)
        XCTAssertEqual(rows, [[0, 1, 2], [3, 4]])
    }

    func testWideEnoughPutsEverythingOnOneRow() {
        let rows = ThumbnailWrapLayout.rows(Array(0..<5), availableWidth: 1_000, itemSize: 88, spacing: 6)
        XCTAssertEqual(rows, [[0, 1, 2, 3, 4]])
    }

    func testTooNarrowForOneImageStillShowsOnePerRow() {
        let columns = ThumbnailWrapLayout.columnsPerRow(availableWidth: 40, itemSize: 88, spacing: 6)
        XCTAssertEqual(columns, 1)
    }

    func testDegenerateInputsNeverReturnZeroColumns() {
        for width in [0, -10, .nan, .infinity] {
            XCTAssertEqual(ThumbnailWrapLayout.columnsPerRow(availableWidth: width, itemSize: 88, spacing: 6),
                           1, "availableWidth \(width)")
        }
        XCTAssertEqual(ThumbnailWrapLayout.columnsPerRow(availableWidth: 291, itemSize: 0, spacing: 6), 1)
        XCTAssertEqual(ThumbnailWrapLayout.columnsPerRow(availableWidth: 291, itemSize: 88, spacing: -6), 3,
                       "负间距按 0 处理：(291 + 0) / 88 = 3，不会因减法算出虚高列数")
    }

    func testRowsKeepOrderAndDropNothing() {
        let rows = ThumbnailWrapLayout.rows(Array(0..<9), availableWidth: 291, itemSize: 88, spacing: 6)
        XCTAssertEqual(rows, [[0, 1, 2], [3, 4, 5], [6, 7, 8]])
        XCTAssertEqual(rows.flatMap { $0 }, Array(0..<9))
    }

    func testEmptyInputProducesNoRows() {
        let none: [[Int]] = []
        XCTAssertEqual(ThumbnailWrapLayout.rows([Int](), availableWidth: 291, itemSize: 88, spacing: 6), none)
    }
}
