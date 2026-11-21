import XCTest
@testable import DSHKit

final class LatencySeriesTests: XCTestCase {
    func testRecordsSamplesInOrder() {
        var s = LatencySeries()
        s.record(ms: 10)
        s.record(ms: 12)
        s.record(ms: 9)
        XCTAssertEqual(s.samples, [10, 12, 9])
        XCTAssertEqual(s.latestMs, 9)
    }

    func testFailureIsNilAndCounted() {
        var s = LatencySeries()
        s.record(ms: 10)
        s.record(ms: nil)      // 不可达
        s.record(ms: 12)
        XCTAssertEqual(s.samples, [10, nil, 12])
        XCTAssertEqual(s.failureCount, 1)
        XCTAssertEqual(s.reachableCount, 2)
        XCTAssertEqual(s.failureIndices, [1])
    }

    func testInvalidLatencyTreatedAsFailure() {
        // 负数是异常采样，不能当成 0ms 画进曲线。
        var s = LatencySeries()
        s.record(ms: -1)
        s.record(ms: 0)
        XCTAssertEqual(s.failureCount, 2)
        XCTAssertEqual(s.reachableCount, 0)
    }

    func testRollingCapacityDropsOldest() {
        var s = LatencySeries(capacity: 3)
        for v in [1, 2, 3, 4, 5] { s.record(ms: v) }
        XCTAssertEqual(s.samples, [3, 4, 5])
    }

    func testMinMaxAndPlotRange() {
        var s = LatencySeries()
        for v in [10, 50, 20] { s.record(ms: v) }
        XCTAssertEqual(s.minimumMs, 10)
        XCTAssertEqual(s.maximumMs, 50)
        XCTAssertEqual(s.plotRange, 10.0...50.0)
    }

    func testFlatSeriesGetsPadding() {
        // 全是同一个值时，曲线不能贴边，否则看起来像 0 基线。
        var s = LatencySeries()
        for _ in 0..<3 { s.record(ms: 20) }
        let range = s.plotRange
        XCTAssertNotNil(range)
        XCTAssertTrue(range!.lowerBound < 20)
        XCTAssertTrue(range!.upperBound > 20)
    }

    func testEmptySeriesHasNoPlotRange() {
        let s = LatencySeries()
        XCTAssertNil(s.plotRange)
        XCTAssertNil(s.latestMs)
        XCTAssertEqual(s.failureCount, 0)
    }

    func testAllFailuresHasNoPlotRange() {
        // 全失败时不该画曲线（没有纵轴范围可定）。
        var s = LatencySeries()
        s.record(ms: nil)
        s.record(ms: nil)
        XCTAssertNil(s.plotRange)
        XCTAssertEqual(s.failureCount, 2)
    }
}
