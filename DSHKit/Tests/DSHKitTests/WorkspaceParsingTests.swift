import XCTest
@testable import DSHKit

final class WorkspaceParsingTests: XCTestCase {
    private func baseline(_ items: [[String: Any]]) -> [String: Any] {
        ["type": "baseline", "value": ["items": items]]
    }

    func testParsesBaselineItems() {
        let frame = baseline([
            ["workspaceId": "w1", "path": "/Users/x/proj-a", "title": "proj-a",
             "sessionIds": ["s1", "s2", "s3"]],
            ["workspaceId": "w2", "path": "/Users/x/proj-b/", "sessionIds": []]
        ])
        let result = WorkspaceParsing.summaries(fromBaselineFrame: frame)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].workspaceId, "w1")
        XCTAssertEqual(result[0].title, "proj-a")
        XCTAssertEqual(result[0].sessionCount, 3)
        // 没有 title 时用路径最后一段（去掉尾斜杠）
        XCTAssertEqual(result[1].title, "proj-b")
        XCTAssertEqual(result[1].sessionCount, 0)
    }

    func testSkipsItemsWithoutWorkspaceId() {
        // 没有 id 就无法传给 session/create，必须跳过而不是造一个空 id。
        let frame = baseline([
            ["path": "/tmp/no-id", "title": "坏数据"],
            ["workspaceId": "good", "path": "/tmp/good"]
        ])
        let result = WorkspaceParsing.summaries(fromBaselineFrame: frame)
        XCTAssertEqual(result.map(\.workspaceId), ["good"])
    }

    func testEmptyItemsReturnsEmpty() {
        XCTAssertTrue(WorkspaceParsing.summaries(fromBaselineFrame: baseline([])).isEmpty)
        XCTAssertTrue(WorkspaceParsing.summaries(fromBaselineFrame: [:]).isEmpty)
    }

    func testDefaultWorkspaceIdExtraction() {
        let value: [String: Any] = ["workspace": ["workspaceId": "default-1"]]
        XCTAssertEqual(WorkspaceParsing.defaultWorkspaceId(fromInitialize: value), "default-1")
        XCTAssertNil(WorkspaceParsing.defaultWorkspaceId(fromInitialize: ["workspace": [:]]))
        XCTAssertNil(WorkspaceParsing.defaultWorkspaceId(fromInitialize: [:]))
    }

    func testPreselectionFallsBackWhenLastUsedDeleted() {
        let available = [
            WorkspaceSummary(workspaceId: "w1", path: "/a", title: "a", sessionCount: 1),
            WorkspaceSummary(workspaceId: "w2", path: "/b", title: "b", sessionCount: 2)
        ]
        // 上次用的还在 → 用它
        XCTAssertEqual(WorkspaceParsing.preselectedId(lastUsed: "w2", defaultId: "w1", available: available), "w2")
        // 上次用的被删了 → 回退默认
        XCTAssertEqual(WorkspaceParsing.preselectedId(lastUsed: "gone", defaultId: "w1", available: available), "w1")
        // 默认也不在 → 取第一项
        XCTAssertEqual(WorkspaceParsing.preselectedId(lastUsed: nil, defaultId: "gone", available: available), "w1")
        // 空列表 → nil
        XCTAssertNil(WorkspaceParsing.preselectedId(lastUsed: "w1", defaultId: "w1", available: []))
    }
}

final class WorkspaceOrderingTests: XCTestCase {
    private func ws(_ id: String, _ title: String, active: TimeInterval?) -> WorkspaceSummary {
        WorkspaceSummary(workspaceId: id, path: "/p/\(title)", title: title,
                         sessionCount: 0, lastActiveAt: active)
    }

    func testDefaultWorkspaceAlwaysFirst() {
        // 默认工作区就算最不活跃也要排第一——它是新建会话的落点。
        let list = [ws("a", "alpha", active: 900),
                    ws("b", "beta", active: 500),
                    ws("d", "default", active: 100)]
        let ordered = WorkspaceParsing.orderedForPicker(list, defaultId: "d")
        XCTAssertEqual(ordered.map(\.workspaceId), ["d", "a", "b"])
    }

    func testRestSortedByActivityDescending() {
        let list = [ws("a", "alpha", active: 100),
                    ws("b", "beta", active: 900),
                    ws("c", "gamma", active: 500)]
        let ordered = WorkspaceParsing.orderedForPicker(list, defaultId: nil)
        XCTAssertEqual(ordered.map(\.workspaceId), ["b", "c", "a"])
    }

    func testWorkspacesWithoutActivityGoLast() {
        let list = [ws("a", "alpha", active: nil),
                    ws("b", "beta", active: 100),
                    ws("c", "gamma", active: nil)]
        let ordered = WorkspaceParsing.orderedForPicker(list, defaultId: nil)
        XCTAssertEqual(ordered.map(\.workspaceId), ["b", "a", "c"])
    }

    func testDefaultMissingFromListKeepsPlainOrder() {
        let list = [ws("a", "alpha", active: 100)]
        XCTAssertEqual(WorkspaceParsing.orderedForPicker(list, defaultId: "gone").map(\.workspaceId), ["a"])
    }
}
