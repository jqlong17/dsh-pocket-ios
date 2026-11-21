import XCTest
@testable import DSHKit

final class AddressStabilityWindowTests: XCTestCase {
    // MARK: - 核心回归：不同地址绝不混算

    func testSeparateAddressesDoNotMix() {
        // 这是本次要修的那个真 bug：全局窗口在切换地址后会串数据，
        // 导致「失败 2 次」分不清是局域网还是 Tailscale 造成的。
        var window = AddressStabilityWindow()
        let lan = "http://192.168.1.18:3091"
        let tail = "https://a.example.ts.net"

        for _ in 0..<10 { window.record(address: lan, connected: true) }
        for _ in 0..<10 { window.record(address: tail, connected: false) }

        XCTAssertEqual(window.stability(for: lan).grade, .stable)
        XCTAssertEqual(window.stability(for: tail).grade, .poor)
        XCTAssertEqual(window.stability(for: lan).healthy, 10)
        XCTAssertEqual(window.stability(for: tail).healthy, 0)
    }

    // MARK: - 等级阈值

    func testGradesByRatio() {
        var window = AddressStabilityWindow()
        let addr = "http://a:1"

        // 全健康 → 稳定
        for _ in 0..<5 { window.record(address: addr, connected: true) }
        XCTAssertEqual(window.stability(for: addr).grade, .stable)

        // 8/10 健康 = 80% → 偶尔抖动
        var w2 = AddressStabilityWindow()
        for _ in 0..<8 { w2.record(address: addr, connected: true) }
        for _ in 0..<2 { w2.record(address: addr, connected: false) }
        XCTAssertEqual(w2.stability(for: addr).grade, .occasional)

        // 5/10 健康 = 50% → 较不稳定
        var w3 = AddressStabilityWindow()
        for _ in 0..<5 { w3.record(address: addr, connected: true) }
        for _ in 0..<5 { w3.record(address: addr, connected: false) }
        XCTAssertEqual(w3.stability(for: addr).grade, .unstable)

        // 4/10 = 40% → 频繁断连
        var w4 = AddressStabilityWindow()
        for _ in 0..<4 { w4.record(address: addr, connected: true) }
        for _ in 0..<6 { w4.record(address: addr, connected: false) }
        XCTAssertEqual(w4.stability(for: addr).grade, .poor)
    }

    func testTooFewSamplesIsUnknown() {
        // 只有 1-2 个样本时不下结论：一次抖动就报「不稳定」会吓到用户。
        var window = AddressStabilityWindow()
        let addr = "http://a:1"
        window.record(address: addr, connected: false)
        XCTAssertEqual(window.stability(for: addr).grade, .unknown)

        window.record(address: addr, connected: false)
        XCTAssertEqual(window.stability(for: addr).grade, .unknown)

        window.record(address: addr, connected: true)
        XCTAssertNotEqual(window.stability(for: addr).grade, .unknown)
    }

    func testUnknownAddressIsEmpty() {
        let window = AddressStabilityWindow()
        let s = window.stability(for: "http://never-probed:1")
        XCTAssertEqual(s.samples, 0)
        XCTAssertEqual(s.grade, .unknown)
    }

    // MARK: - 滚动窗口

    func testRollingWindowDropsOldSamples() {
        // 容量 5：先记 5 次失败，再记 5 次成功，应该只剩最近 5 次（全成功）。
        var window = AddressStabilityWindow(capacity: 5)
        let addr = "http://a:1"
        for _ in 0..<5 { window.record(address: addr, connected: false) }
        for _ in 0..<5 { window.record(address: addr, connected: true) }

        let s = window.stability(for: addr)
        XCTAssertEqual(s.samples, 5)
        XCTAssertEqual(s.healthy, 5)
        XCTAssertEqual(s.grade, .stable)
    }

    func testRetainDropsRemovedAddresses() {
        // 用户删掉一条地址后，它的窗口不该继续占内存。
        var window = AddressStabilityWindow()
        let keep = "http://keep:1"
        let drop = "http://drop:1"
        for _ in 0..<4 { window.record(address: keep, connected: true) }
        for _ in 0..<4 { window.record(address: drop, connected: false) }

        window.retain(addresses: [keep])
        XCTAssertEqual(window.stability(for: keep).samples, 4)
        XCTAssertEqual(window.stability(for: drop).samples, 0)
    }
}
