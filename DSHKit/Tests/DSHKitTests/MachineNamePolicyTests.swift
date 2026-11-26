import XCTest
@testable import DSHKit

final class MachineNamePolicyTests: XCTestCase {
    func testHeaderWins() {
        XCTAssertEqual(MachineNamePolicy.resolve(header: "ruskadeMacBook-Pro.local"), "ruskadeMacBook-Pro.local")
    }

    func testMissingHeaderClearsInsteadOfInheriting() {
        // 回归：以前会沿用上一台机器的名字，导致两台不同 DSH 被合并成一台
        XCTAssertNil(MachineNamePolicy.resolve(header: nil, previous: "ruskadeMacBook-Pro.local"))
    }

    func testBlankHeaderIsUnknown() {
        XCTAssertNil(MachineNamePolicy.resolve(header: "   "))
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(MachineNamePolicy.resolve(header: " iZ2zedykjgnnou1hihecizZ "), "iZ2zedykjgnnou1hihecizZ")
    }
}
