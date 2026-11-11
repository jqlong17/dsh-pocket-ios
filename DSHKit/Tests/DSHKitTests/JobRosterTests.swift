import XCTest
@testable import DSHKit

final class JobRosterTests: XCTestCase {
    func testParsesFullRow() {
        let row = DSHJobRow(json: [
            "id": "job-1",
            "kind": "bash",
            "label": "跑测试",
            "status": "running",
            "startedAt": 1_700_000_000_000,
            "progress": "3/10",
            "detail": "swift test"
        ])
        XCTAssertEqual(row?.id, "job-1")
        XCTAssertEqual(row?.kind, "bash")
        XCTAssertEqual(row?.label, "跑测试")
        XCTAssertEqual(row?.startedAt, 1_700_000_000_000)
        XCTAssertEqual(row?.progress, "3/10")
        XCTAssertTrue(row?.isRunning ?? false)
    }

    func testStoppingCountsAsRunning() {
        XCTAssertTrue(DSHJobRow(json: ["id": "a", "status": "stopping"])?.isRunning ?? false)
    }

    func testFinishedIsNotRunning() {
        let row = DSHJobRow(json: ["id": "a", "status": "done", "finishedAt": 10])
        XCTAssertFalse(row?.isRunning ?? true)
        XCTAssertEqual(row?.finishedAt, 10)
    }

    func testMissingIdIsRejected() {
        XCTAssertNil(DSHJobRow(json: ["status": "running"]))
        XCTAssertNil(DSHJobRow(json: ["id": "", "status": "running"]))
    }

    func testMissingFieldsFallBackToEmpty() {
        let row = DSHJobRow(json: ["id": "a"])
        XCTAssertEqual(row?.kind, "")
        XCTAssertEqual(row?.status, "")
        XCTAssertEqual(row?.startedAt, 0)
        XCTAssertNil(row?.progress)
    }

    func testRosterParsesListAndDropsBadRows() {
        let value: [String: Any] = [
            "jobs": [
                ["id": "a", "status": "running"],
                ["status": "running"],
                ["id": "b", "status": "done"]
            ]
        ]
        let rows = DSHJobRoster.rows(fromValue: value)
        XCTAssertEqual(rows?.map(\.id), ["a", "b"])
    }

    func testRosterReturnsNilWhenFrameIsNotARoster() {
        XCTAssertNil(DSHJobRoster.rows(fromValue: ["messages": []]))
    }

    func testRosterAcceptsEmptyList() {
        XCTAssertEqual(DSHJobRoster.rows(fromValue: ["jobs": []])?.count, 0)
    }
}
