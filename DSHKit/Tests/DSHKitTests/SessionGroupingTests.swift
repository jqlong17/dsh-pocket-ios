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

// 回归：服务端列表出现过重复 sessionId，用 Dictionary(uniqueKeysWithValues:) 会 fatalError。
// 2026-11-12 真机闪退就是这个：Fatal error: Dictionary literal contains duplicate keys。
final class SessionGroupingDuplicateTests: XCTestCase {
    private func item(_ id: String, _ cwd: String?) -> SessionGrouping.Item {
        .init(sessionId: id, cwd: cwd)
    }

    func testDuplicateSessionIdsDoNotCrash() {
        let items = [item("a", "/p/one"), item("a", "/p/one"), item("b", "/p/two")]
        let groups = SessionGrouping.groups(items: items, pinnedIds: ["a"])
        XCTAssertEqual(groups.first?.sessionIds, ["a"])
        XCTAssertEqual(groups.last?.sessionIds, ["b"])
    }

    func testDuplicateIdsInDisplayOrderKeepFirst() {
        // 与原实现等价：置顶取第一个，其余过滤掉所有同 id，所以重复 id 最终只出现一次。
        let items = [item("a", nil), item("a", nil)]
        XCTAssertEqual(SessionGrouping.displayOrder(items: items, pinnedIds: ["a"]), ["a"])
    }
}

final class SessionGroupingDirectoryOrderTests: XCTestCase {
    private func items() -> [SessionGrouping.Item] {
        [
            .init(sessionId: "a", cwd: "/p/alpha"),
            .init(sessionId: "b", cwd: "/p/beta"),
            .init(sessionId: "c", cwd: "/p/gamma"),
            .init(sessionId: "d", cwd: "/p/alpha")
        ]
    }

    func testDefaultOrderIsFirstAppearance() {
        let groups = SessionGrouping.groups(items: items(), pinnedIds: [])
        XCTAssertEqual(groups.map(\.id), ["/p/alpha", "/p/beta", "/p/gamma"])
    }

    func testExplicitDirectoryOrderWins() {
        // 用户拖动后，顺序应完全跟 workspace 列表走，而不是按会话出现先后。
        let groups = SessionGrouping.groups(items: items(), pinnedIds: [],
                                            directoryOrder: ["/p/gamma", "/p/alpha", "/p/beta"])
        XCTAssertEqual(groups.map(\.id), ["/p/gamma", "/p/alpha", "/p/beta"])
    }

    func testDirectoriesMissingFromOrderGoLastInOriginalOrder() {
        // workspace 列表可能落后于会话（新目录还没出现在列表里）：这些排后面，不丢。
        let groups = SessionGrouping.groups(items: items(), pinnedIds: [],
                                            directoryOrder: ["/p/gamma"])
        XCTAssertEqual(groups.map(\.id), ["/p/gamma", "/p/alpha", "/p/beta"])
    }

    func testPinnedGroupStaysFirstRegardlessOfOrder() {
        let groups = SessionGrouping.groups(items: items(), pinnedIds: ["b"],
                                            directoryOrder: ["/p/gamma"])
        XCTAssertEqual(groups.first?.id, SessionGrouping.pinnedGroupId)
        XCTAssertTrue(groups.first?.isPinned == true)
    }
}
