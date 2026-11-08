import XCTest
@testable import DSHKit

final class SessionTests: XCTestCase {
    private func sessions() throws -> [DSHSession] {
        let json = try fixtureJSON("session_list")
        let items = try XCTUnwrap(json["items"] as? [[String: Any]])
        return items.compactMap(DSHDecoding.session(fromJSON:))
    }

    // P30
    func testArchivedSessionsAreFilteredOut() throws {
        let visible = DSHSession.visible(in: try sessions(), archivedSessionIds: ["session-archived-1"])
        XCTAssertFalse(visible.contains { $0.sessionId == "session-archived-1" })
        XCTAssertTrue(visible.contains { $0.sessionId == "session-normal-1" })
    }

    // P31
    func testSubagentSessionsAreHidden() throws {
        let visible = DSHSession.visible(in: try sessions(), archivedSessionIds: [])
        XCTAssertFalse(visible.contains { $0.sessionId == "session-subagent-1" })
    }

    // P32
    func testBlankSessionsAreHidden() throws {
        let visible = DSHSession.visible(in: try sessions(), archivedSessionIds: [])
        XCTAssertFalse(visible.contains { $0.sessionId == "session-blank-1" })
    }

    // P33
    func testSessionProjectionFields() throws {
        let normal = try XCTUnwrap(try sessions().first { $0.sessionId == "session-normal-1" })
        XCTAssertEqual(normal.title, "给项目加一个登录页")
        XCTAssertTrue(normal.running)
        XCTAssertEqual(normal.updatedAt, 1794177753606)
        XCTAssertEqual(normal.cwd, "/Users/me/work/demo")
        XCTAssertFalse(normal.isSubagent)
        XCTAssertTrue(normal.isVisibleInList)
    }
}
