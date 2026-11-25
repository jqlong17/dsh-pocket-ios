import XCTest
@testable import DSHKit

final class HostNamingTests: XCTestCase {
    func testEmptyGivesFirst() {
        XCTAssertEqual(HostNaming.nextName(existing: []), "DSH 1")
    }

    func testSkipsExactNames() {
        XCTAssertEqual(HostNaming.nextName(existing: ["DSH 1", "DSH 2"]), "DSH 3")
    }

    /// 回归：用户把 DSH 2 改名成「DSH 2 阿里云」后，DSH 2 不能被再次分配。
    func testSkipsRenamedHosts() {
        XCTAssertEqual(HostNaming.nextName(existing: ["DSH 1", "DSH 2 阿里云"]), "DSH 3")
    }

    /// 回归：DSH 20 不能被认为占用了 DSH 2。
    func testDoesNotConfuseDoubleDigits() {
        XCTAssertFalse(HostNaming.isTakenBy("DSH 20", number: 2))
        XCTAssertEqual(HostNaming.nextName(existing: ["DSH 20"]), "DSH 1")
    }

    func testTakenByVariants() {
        XCTAssertTrue(HostNaming.isTakenBy("DSH 2", number: 2))
        XCTAssertTrue(HostNaming.isTakenBy("DSH 2 阿里云", number: 2))
        XCTAssertTrue(HostNaming.isTakenBy("DSH 2（公司）", number: 2))
        XCTAssertFalse(HostNaming.isTakenBy("DSH 3", number: 2))
        XCTAssertFalse(HostNaming.isTakenBy("Mac", number: 2))
    }
}
