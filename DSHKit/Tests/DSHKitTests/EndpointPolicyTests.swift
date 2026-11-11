import XCTest
@testable import DSHKit

final class EndpointPolicyTests: XCTestCase {
    func testKindClassifiesLanHosts() {
        XCTAssertEqual(DSHEndpointPolicy.kind(of: "http://localhost:3081"), .lan)
        XCTAssertEqual(DSHEndpointPolicy.kind(of: "http://mac.local:3081"), .lan)
        XCTAssertEqual(DSHEndpointPolicy.kind(of: "http://127.0.0.1:3081"), .lan)
        XCTAssertEqual(DSHEndpointPolicy.kind(of: "http://10.0.0.8:3081"), .lan)
        XCTAssertEqual(DSHEndpointPolicy.kind(of: "http://192.168.1.10:3081"), .lan)
        XCTAssertEqual(DSHEndpointPolicy.kind(of: "http://172.16.0.2:3081"), .lan)
        XCTAssertEqual(DSHEndpointPolicy.kind(of: "http://172.31.255.1:3081"), .lan)
    }

    func testKindClassifiesPublicAndCustom() {
        XCTAssertEqual(DSHEndpointPolicy.kind(of: "https://example.trycloudflare.com"), .publicNetwork)
        XCTAssertEqual(DSHEndpointPolicy.kind(of: "http://foo.trycloudflare.com:443"), .publicNetwork)
        XCTAssertEqual(DSHEndpointPolicy.kind(of: "https://studio.example.ts.net"), .publicNetwork)
        XCTAssertEqual(DSHEndpointPolicy.kind(of: "http://203.0.113.10:3091"), .custom)
        XCTAssertEqual(DSHEndpointPolicy.kind(of: "not a url"), .custom)
    }

    func testDedupKeepsQuotasAndMostRecent() {
        let now = 1_000.0
        let list = [
            rec("http://192.168.1.11:3081", .lan, now + 1, "家"),
            rec("http://192.168.1.12:3081", .lan, now + 2, "公司"),
            rec("http://192.168.1.13:3081", .lan, now + 3, "咖啡馆"),
            rec("http://192.168.1.14:3081", .lan, now, "旧的"),
            rec("https://a.example.ts.net", .publicNetwork, now + 5, nil),
            rec("https://b.example.ts.net", .publicNetwork, now + 1, nil),
            rec("http://203.0.113.10:3091", .custom, now + 4, "服务器"),
            rec("http://203.0.113.11:3091", .custom, now + 3, "另一台"),
            rec("http://203.0.113.12:3091", .custom, now, "超配额"),
            rec("http://192.168.1.11:3081", .lan, now + 9, "家-重复"),
        ]
        let kept = DSHEndpointPolicy.dedup(list)
        let addresses = kept.map(\.address)
        XCTAssertEqual(addresses.filter { DSHEndpointPolicy.kind(of: $0) == .lan || $0.contains("192.168") }.count, 3)
        XCTAssertTrue(addresses.contains("http://192.168.1.13:3081"))
        XCTAssertTrue(addresses.contains("http://192.168.1.12:3081"))
        XCTAssertTrue(addresses.contains("http://192.168.1.11:3081"))
        XCTAssertFalse(addresses.contains("http://192.168.1.14:3081"))
        XCTAssertEqual(addresses.filter { $0.contains("example.ts.net") }, ["https://a.example.ts.net"])
        XCTAssertTrue(addresses.contains("http://203.0.113.10:3091"))
        XCTAssertTrue(addresses.contains("http://203.0.113.11:3091"))
        XCTAssertFalse(addresses.contains("http://203.0.113.12:3091"))
        XCTAssertEqual(kept.first(where: { $0.address == "http://192.168.1.11:3081" })?.label, "家-重复")
    }

    func testReleaseBuildDoesNotAutoSeedAndLeavesExistingListUnchanged() {
        let existing = ["http://192.168.1.10:3081", "http://203.0.113.10:3091"]
        XCTAssertFalse(
            DSHEndpointPolicy.shouldAutoSeedDevelopmentEndpoint(
                isDebugBuild: false,
                existingAddresses: existing,
                developmentAddress: "http://203.0.113.10:3091"
            )
        )
        XCTAssertFalse(
            DSHEndpointPolicy.shouldAutoSeedDevelopmentEndpoint(
                isDebugBuild: false,
                existingAddresses: [],
                developmentAddress: "http://203.0.113.10:3091"
            )
        )
        XCTAssertEqual(existing, ["http://192.168.1.10:3081", "http://203.0.113.10:3091"])
    }

    func testDebugBuildSeedsOnlyWhenAddressMissing() {
        XCTAssertTrue(
            DSHEndpointPolicy.shouldAutoSeedDevelopmentEndpoint(
                isDebugBuild: true,
                existingAddresses: ["http://192.168.1.10:3081"],
                developmentAddress: "http://203.0.113.10:3091"
            )
        )
        XCTAssertFalse(
            DSHEndpointPolicy.shouldAutoSeedDevelopmentEndpoint(
                isDebugBuild: true,
                existingAddresses: ["http://203.0.113.10:3091", "http://192.168.1.10:3081"],
                developmentAddress: "http://203.0.113.10:3091"
            )
        )
    }

    func testDedupDoesNotDropManuallySavedEndpointsWithinQuota() {
        let list = [
            rec("http://192.168.1.10:3081", .lan, 2, "家"),
            rec("http://203.0.113.10:3091", .custom, 1, "服务器"),
        ]
        let kept = DSHEndpointPolicy.dedup(list)
        XCTAssertEqual(Set(kept.map(\.address)), ["http://192.168.1.10:3081", "http://203.0.113.10:3091"])
        XCTAssertEqual(kept.first(where: { $0.address == "http://192.168.1.10:3081" })?.label, "家")
    }

    private func rec(_ address: String, _ kind: DSHEndpointKind, _ lastUsedAt: Double, _ label: String?) -> DSHSavedEndpointRecord {
        DSHSavedEndpointRecord(address: address, kind: kind, lastUsedAt: lastUsedAt, label: label)
    }
}
