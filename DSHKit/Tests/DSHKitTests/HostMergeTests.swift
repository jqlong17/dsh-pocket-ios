import XCTest
@testable import DSHKit

final class HostMergeTests: XCTestCase {
    func testNoDuplicates() {
        XCTAssertTrue(HostMerge.duplicateGroups(machines: ["mac", nil, "aliyun"]).isEmpty)
    }

    func testFindsDuplicateMachine() {
        let groups = HostMerge.duplicateGroups(machines: ["mac", "aliyun", "mac"])
        XCTAssertEqual(groups, [[0, 2]])
    }

    func testNilMachinesAreNeverMerged() {
        XCTAssertTrue(HostMerge.duplicateGroups(machines: [nil, nil, ""]).isEmpty)
    }

    func testKeeperPrefersCurrent() {
        let keeper = HostMerge.keeper(in: [0, 2], currentIndex: 2, lastUsedAt: [10, 0, 5])
        XCTAssertEqual(keeper, 2)
    }

    func testKeeperFallsBackToMostRecent() {
        let keeper = HostMerge.keeper(in: [0, 2], currentIndex: nil, lastUsedAt: [10, 0, 99])
        XCTAssertEqual(keeper, 2)
    }
}
