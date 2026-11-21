import XCTest
@testable import DSHKit

final class RoutePolicyTests: XCTestCase {
    private func candidate(_ address: String, kind: DSHEndpointKind, reachable: Bool, rtt: Int?) -> RouteCandidate {
        RouteCandidate(address: address, kind: kind, reachable: reachable, rttMs: rtt)
    }

    func testManualPreferenceNeverSwitches() {
        // 用户手选过的路不该被悄悄改掉——这是开关默认关闭的原因，也是最容易出事的地方。
        let lan = candidate("http://192.168.1.18:3091", kind: .lan, reachable: true, rtt: 5)
        let ts = candidate("https://a.ts.net", kind: .publicNetwork, reachable: true, rtt: 300)
        XCTAssertNil(RoutePolicy.choose(from: [lan, ts], preference: .manual))
    }

    func testLanWinsWhenReachable() {
        // 局域网 RTT 更大也要选它：省掉的是固定的 TLS 握手 + 隧道开销，
        // 比几毫秒的 RTT 差异值钱得多。
        let lan = candidate("http://192.168.1.18:3091", kind: .lan, reachable: true, rtt: 300)
        let ts = candidate("https://a.ts.net", kind: .publicNetwork, reachable: true, rtt: 10)
        XCTAssertEqual(RoutePolicy.choose(from: [lan, ts], preference: .lanFirst), "http://192.168.1.18:3091")
    }

    func testFallsBackToFastestWhenLanDown() {
        // 手机离开家里：局域网不可达，应切到最快的公网地址。
        let lan = candidate("http://192.168.1.18:3091", kind: .lan, reachable: false, rtt: nil)
        let slow = candidate("https://slow.ts.net", kind: .publicNetwork, reachable: true, rtt: 200)
        let fast = candidate("https://fast.ts.net", kind: .publicNetwork, reachable: true, rtt: 30)
        XCTAssertEqual(RoutePolicy.choose(from: [lan, slow, fast], preference: .lanFirst), "https://fast.ts.net")
    }

    func testPicksFastestAmongMultipleLan() {
        let a = candidate("http://192.168.1.18:3091", kind: .lan, reachable: true, rtt: 40)
        let b = candidate("http://192.168.1.20:3091", kind: .lan, reachable: true, rtt: 3)
        XCTAssertEqual(RoutePolicy.choose(from: [a, b], preference: .lanFirst), "http://192.168.1.20:3091")
    }

    func testAllUnreachableReturnsNil() {
        // 宁可保持现状，也不切到一个已知不通的地址。
        let a = candidate("http://192.168.1.18:3091", kind: .lan, reachable: false, rtt: nil)
        let b = candidate("https://a.ts.net", kind: .publicNetwork, reachable: false, rtt: nil)
        XCTAssertNil(RoutePolicy.choose(from: [a, b], preference: .lanFirst))
    }

    func testNilRTTRanksLastButSelectable() {
        // 只做了 TCP 探测的候选（没有 RTT）可以选，但排在测到 RTT 的后面。
        let noRTT = candidate("https://tcp-only.ts.net", kind: .publicNetwork, reachable: true, rtt: nil)
        let withRTT = candidate("https://measured.ts.net", kind: .publicNetwork, reachable: true, rtt: 500)
        XCTAssertEqual(RoutePolicy.choose(from: [noRTT, withRTT], preference: .lanFirst), "https://measured.ts.net")

        // 只有无 RTT 的候选时，仍然要选一个（能连总比不连强）
        XCTAssertEqual(RoutePolicy.choose(from: [noRTT], preference: .lanFirst), "https://tcp-only.ts.net")
    }

    func testEmptyCandidatesReturnsNil() {
        XCTAssertNil(RoutePolicy.choose(from: [], preference: .lanFirst))
    }

    func testTieIsStable() {
        // 同 RTT 时必须稳定（按地址排序），否则每次选到不同地址会让 UI 抖动。
        let a = candidate("https://b.ts.net", kind: .publicNetwork, reachable: true, rtt: 20)
        let b = candidate("https://a.ts.net", kind: .publicNetwork, reachable: true, rtt: 20)
        XCTAssertEqual(RoutePolicy.choose(from: [a, b], preference: .lanFirst), "https://a.ts.net")
        XCTAssertEqual(RoutePolicy.choose(from: [b, a], preference: .lanFirst), "https://a.ts.net")
    }
}
