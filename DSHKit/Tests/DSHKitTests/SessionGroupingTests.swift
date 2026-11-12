import XCTest
@testable import DSHKit

final class SessionGroupingTests: XCTestCase {
    private func item(_ id: String, _ cwd: String?) -> SessionGrouping.Item {
        .init(sessionId: id, cwd: cwd)
    }

    func testPinnedGroupComesFirst() {
        let items = [item("a", "/p/one"), item("b", "/p/two")]
        let groups = SessionGrouping.groups(items: items, pinnedIds: ["b"])
        XCTAssertEqual(groups.first?.id, SessionGrouping.pinnedGroupId)
        XCTAssertEqual(groups.first?.sessionIds, ["b"])
        XCTAssertTrue(groups.first?.isPinned ?? false)
    }

    func testGroupedByWorkspaceFolderInFirstAppearanceOrder() {
        let items = [item("a", "/work/alpha"), item("b", "/work/beta"), item("c", "/work/alpha")]
        let groups = SessionGrouping.groups(items: items, pinnedIds: [])
        XCTAssertEqual(groups.map(\.folder), ["alpha", "beta"])
        XCTAssertEqual(groups.first?.sessionIds, ["a", "c"])
    }

    func testMissingCwdGoesToOther() {
        let items = [item("a", nil), item("b", "  ")]
        let groups = SessionGrouping.groups(items: items, pinnedIds: [])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.id, SessionGrouping.otherGroupId)
        XCTAssertNil(groups.first?.folder)
        XCTAssertEqual(groups.first?.sessionIds, ["a", "b"])
    }

    func testDisplayOrderPutsPinnedFirstThenKeepsRest() {
        let items = [item("a", nil), item("b", nil), item("c", nil)]
        XCTAssertEqual(SessionGrouping.displayOrder(items: items, pinnedIds: ["c"]), ["c", "a", "b"])
    }

    func testDisplayOrderWithoutPinsIsUnchanged() {
        let items = [item("a", nil), item("b", nil)]
        XCTAssertEqual(SessionGrouping.displayOrder(items: items, pinnedIds: []), ["a", "b"])
    }
}
