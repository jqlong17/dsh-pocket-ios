import XCTest
@testable import DSHKit

final class WorkspaceBaselineTests: XCTestCase {
    private func frame(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    func testDecodesBaseline() throws {
        let data = frame([
            "streamId": "s1", "type": "item",
            "value": ["type": "baseline",
                      "value": ["archivedSessionIds": ["a", "b"], "pinnedSessionIds": ["c"]]],
        ])
        guard case .baseline(let decoded) = WorkspaceBaseline.decode(frame: data, streamId: "s1") else {
            return XCTFail("应解析出基线")
        }
        XCTAssertEqual(decoded.archived, ["a", "b"])
        XCTAssertEqual(decoded.pinned, ["c"])
    }

    func testPinnedDefaultsToEmpty() throws {
        let data = frame([
            "streamId": "s1", "type": "item",
            "value": ["type": "baseline", "value": ["archivedSessionIds": ["a"]]],
        ])
        guard case .baseline(let decoded) = WorkspaceBaseline.decode(frame: data, streamId: "s1") else {
            return XCTFail("应解析出基线")
        }
        XCTAssertTrue(decoded.pinned.isEmpty)
    }

    func testSkipsOtherStreamsAndNonBaseline() {
        let otherStream = frame(["streamId": "x", "type": "item", "value": ["type": "baseline", "value": [:]]])
        XCTAssertEqual(WorkspaceBaseline.decode(frame: otherStream, streamId: "s1"), .skip)

        let item = frame(["streamId": "s1", "type": "item", "value": ["type": "delta", "value": [:] as [String: Any]]])
        XCTAssertEqual(WorkspaceBaseline.decode(frame: item, streamId: "s1"), .skip)

        let notJSON = Data("nonsense".utf8)
        XCTAssertEqual(WorkspaceBaseline.decode(frame: notJSON, streamId: "s1"), .skip)
    }

    func testMalformedBaselineIsReported() {
        let data = frame(["streamId": "s1", "type": "item",
                          "value": ["type": "baseline", "value": ["archivedSessionIds": "oops"]]])
        XCTAssertEqual(WorkspaceBaseline.decode(frame: data, streamId: "s1"), .malformed)
    }
}
