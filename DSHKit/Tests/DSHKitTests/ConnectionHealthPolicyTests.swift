import XCTest
@testable import DSHKit

final class ConnectionHealthPolicyTests: XCTestCase {
    // MARK: - 探测方式按网络类型自适应

    func testWiFiUsesHTTPProbe() {
        // Wi-Fi 流量免费，用 HTTP 才能拿到 RTT（用户就是要看「哪条快」）。
        XCTAssertEqual(ConnectionHealthPolicy.strategy(for: .wifi), .http)
    }

    func testCellularUsesTCPProbe() {
        // 蜂窝下 HTTPS 每次要重做 TLS 握手（约 5 KB），60 秒一轮会吃掉几百 MB/月。
        // 这条断言是流量约束的守门人：改成 .http 会静默烧流量。
        XCTAssertEqual(ConnectionHealthPolicy.strategy(for: .cellular), .tcp)
    }

    func testUnknownNetworkFallsBackToTCP() {
        // 不能返回 .none：NWPathMonitor 首次回调前 networkClass 就是 .other，
        // 那时跳过探测会让所有地址恒被标成不可达（实测踩过）。
        // 离线时 TCP 自己也会失败，结论仍正确，代价只有 0.2 KB。
        XCTAssertEqual(ConnectionHealthPolicy.strategy(for: .other), .tcp)
    }

    // MARK: - 该不该探

    func testProbesOnlySavedAddresses() {
        let saved = ["http://192.168.1.18:3091", "https://a.example.ts.net"]
        XCTAssertTrue(ConnectionHealthPolicy.shouldProbe(address: saved[0], saved: saved))
        XCTAssertFalse(ConnectionHealthPolicy.shouldProbe(address: "http://203.0.113.1:3091", saved: saved))
    }

    func testEmptyAddressIsNeverProbed() {
        XCTAssertFalse(ConnectionHealthPolicy.shouldProbe(address: "", saved: ["http://a:1"]))
    }

    // MARK: - 结论归纳

    func testUnreachableIsExplicitState() {
        // 关键：不可达必须是**明确的状态**，不能沉默——用户在外面时，
        // 列表里那条局域网地址要写出「不可达」，否则他还要自己试一遍。
        XCTAssertEqual(ConnectionHealthPolicy.summarize(reachable: false, rttMs: nil), .unreachable)
    }

    func testReachableCarriesRTT() {
        XCTAssertEqual(ConnectionHealthPolicy.summarize(reachable: true, rttMs: 18),
                       .reachable(rttMs: 18))
    }

    func testTCPProbeKeepsNilRTT() {
        // TCP 探测没有往返时延可报，不能编一个 0 出来。
        XCTAssertEqual(ConnectionHealthPolicy.summarize(reachable: true, rttMs: nil),
                       .reachable(rttMs: nil))
    }

    func testInvalidRTTIsDropped() {
        // 负数/超大值都是异常采样，当作「没测到」，避免 UI 显示 -1ms。
        XCTAssertEqual(ConnectionHealthPolicy.summarize(reachable: true, rttMs: -1),
                       .reachable(rttMs: nil))
        XCTAssertEqual(ConnectionHealthPolicy.summarize(reachable: true, rttMs: 999_999),
                       .reachable(rttMs: nil))
    }
}
