import XCTest
@testable import DSHKit

final class TimelineAssemblyTests: XCTestCase {
    func testOrdersBySortKeyThenSequence() {
        let items = [
            TimelineSortKey(id: "b", sortKey: 2, sequence: 5, isMessage: true),
            TimelineSortKey(id: "a", sortKey: 1, sequence: 9, isMessage: true),
            TimelineSortKey(id: "c", sortKey: 2, sequence: 3, isMessage: true),
        ]
        XCTAssertEqual(TimelineAssembly.ordered(items).map(\.id), ["a", "c", "b"])
    }

    func testPendingComesBeforeConfirmedOnSameKey() {
        let items = [
            TimelineSortKey(id: "confirmed", sortKey: 3, sequence: 7, isMessage: true, isPending: false),
            TimelineSortKey(id: "pending", sortKey: 3, sequence: 7, isMessage: true, isPending: true),
        ]
        XCTAssertEqual(TimelineAssembly.ordered(items).map(\.id), ["pending", "confirmed"])
    }

    func testSameTurnPendingUsesLocalOrderNotID() {
        // 快速连发两条：id 是随机 UUID，必须用本地顺序，否则会颠倒。
        let items = [
            TimelineSortKey(id: "zzz-uuid", sortKey: 4, sequence: 4, isMessage: true, isPending: true, localOrder: 1),
            TimelineSortKey(id: "aaa-uuid", sortKey: 4, sequence: 4, isMessage: true, isPending: true, localOrder: 2),
        ]
        XCTAssertEqual(TimelineAssembly.ordered(items).map(\.id), ["zzz-uuid", "aaa-uuid"])
    }

    func testMessageBeforeNonMessageOnTie() {
        let items = [
            TimelineSortKey(id: "step", sortKey: 5, sequence: 5, isMessage: false),
            TimelineSortKey(id: "msg", sortKey: 5, sequence: 5, isMessage: true),
        ]
        XCTAssertEqual(TimelineAssembly.ordered(items).map(\.id), ["msg", "step"])
    }

    func testEmptyStaysEmpty() {
        XCTAssertTrue(TimelineAssembly.ordered([]).isEmpty)
    }
}
