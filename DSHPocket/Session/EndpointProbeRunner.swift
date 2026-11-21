import Foundation
import Network
import DSHKit
import Observation

/// 对「已保存的连接地址」做定期健康探测，给设置页提供「哪条现在能用、多快」。
///
/// 三条设计约束（见 spec/2026-11-21-0840）：
/// 1. **流量随网络类型自适应**：Wi-Fi 用 HTTP（免费且能测 RTT），蜂窝只做 TCP
///    （HTTPS 每次要重做 TLS 握手，60 秒一轮会吃掉几百 MB/月）。
/// 2. **只探保存过的地址**：没保存的地址用户不会切过去，探测是纯浪费。
/// 3. **进后台即停**：ScenePhase 不是 active 时不跑定时器。
@Observable
@MainActor
final class EndpointProbeRunner {
    /// 地址 → 最近一次探测结论。
    private(set) var results: [String: HealthState] = [:]
    /// 当前网络类型。Wi-Fi / 蜂窝决定探测方式。
    private(set) var networkClass: NetworkClass = .other
    /// 地址 → 最近一次失败原因。UI 在「不可达」下面显示，便于判断是超时还是拒绝。
    private(set) var lastErrors: [String: String] = [:]
    /// 按地址累积探测历史，供设置页显示「这条稳不稳」。
    private(set) var stability = AddressStabilityWindow()
    /// 按地址累积时延序列，供设置页画迷你曲线（能看出刚才有没有抖）。
    private(set) var latencyHistory: [String: LatencySeries] = [:]

    /// 正常探测周期。60 秒是「够及时」和「流量可忽略」的折中。
    static let normalInterval: Duration = .seconds(60)
    /// 测试模式周期：和遥测同频（10 秒），让「采集中」在 30 秒内变成结论。
    /// 只在用户手动打开测试模式时生效——它会让流量放大 6 倍。
    static let testInterval: Duration = .seconds(10)
    /// TCP 探测超时：超过 3 秒视为不可达。
    static let tcpTimeout: TimeInterval = 3
    /// HTTP 探测超时：5 秒（要覆盖 Tailscale 打洞较慢的情况）。
    static let httpTimeout: TimeInterval = 5

    /// 显式 nonisolated：`ConnectionModel` 在非隔离上下文里用 `lazy` 构造它，
    /// 默认的 @MainActor init 会让那句初始化直接编译失败。
    nonisolated init() {}

    /// 测试模式：更高频探测，用于验证与排查。默认关闭。
    var testMode = false {
        didSet {
            guard testMode != oldValue else { return }
            // 间隔变了要重建循环，否则要等满一个旧周期才生效。
            let addresses = targets
            loop?.cancel()
            loop = nil
            start(addresses: addresses)
        }
    }

    private var interval: Duration {
        testMode ? Self.testInterval : Self.normalInterval
    }

    private let monitor = NWPathMonitor()
    private var loop: Task<Void, Never>?
    private var isMonitoring = false

    deinit {
        monitor.cancel()
    }

    /// 要探测的地址快照。由调用方每次打开设置页时更新。
    private var targets: [String] = []

    /// 开始：先起网络类型监听，再进探测循环。
    func start(addresses: [String] = []) {
        targets = addresses
        guard loop == nil else { return }
        startMonitoringIfNeeded()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                if let targets = self?.targets {
                    await self?.probeRound(addresses: targets)
                }
                let sleepFor = await self?.interval ?? Self.normalInterval
                try? await Task.sleep(for: sleepFor)
            }
        }
    }

    /// 更新要探测的地址（用户在设置页里增删保存的连接时）。
    func update(addresses: [String]) {
        targets = addresses
    }

    /// 停止（进后台时调用）。
    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// 探测一轮。`addresses` 是用户保存的连接地址。
    func probeRound(addresses: [String]) async {
        guard !addresses.isEmpty else { return }
        let strategy = ConnectionHealthPolicy.strategy(for: networkClass)
        guard strategy != .none else {
            // 离线：全部标不可达，比保留上一次的「可达」更诚实。
            for address in addresses { results[address] = .unreachable }
            return
        }
        stability.retain(addresses: Set(addresses))
        latencyHistory = latencyHistory.filter { addresses.contains($0.key) }
        let saved = addresses
        await withTaskGroup(of: (String, (HealthState, String?)).self) { group in
            for address in addresses where ConnectionHealthPolicy.shouldProbe(address: address, saved: saved) {
                group.addTask { [strategy] in
                    let packed = await Self.probe(address: address, strategy: strategy)
                    return (address, packed)
                }
            }
            for await (address, packed) in group {
                let (state, err) = packed
                results[address] = state
                if let err { lastErrors[address] = err } else { lastErrors[address] = nil }
                // 稳定性按地址分别积累：切换地址后不能再混算（2026-11-21 用户反馈）。
                if case .reachable(let rtt) = state {
                    stability.record(address: address, connected: true)
                    latencyHistory[address, default: LatencySeries()].record(ms: rtt)
                } else {
                    stability.record(address: address, connected: false)
                    // 失败点也要记（nil），曲线才能断出缺口。
                    latencyHistory[address, default: LatencySeries()].record(ms: nil)
                }
            }
        }
    }

    // MARK: - 网络类型

    private func startMonitoringIfNeeded() {
        guard !isMonitoring else { return }
        isMonitoring = true
        monitor.pathUpdateHandler = { [weak self] path in
            let kind: NetworkClass
            if path.usesInterfaceType(.wifi) {
                kind = .wifi
            } else if path.usesInterfaceType(.cellular) {
                kind = .cellular
            } else if path.status == .satisfied {
                kind = .other
            } else {
                kind = .other
            }
            Task { @MainActor [weak self] in
                self?.networkClass = kind
            }
        }
        monitor.start(queue: DispatchQueue(label: "dsh.endpoint-probe.path"))
    }

    // MARK: - 单条探测

    /// 按策略探测一条地址。失败一律返回 `.unreachable`，不抛错——
    /// 这是展示用数据，不该让调用方处理异常分支。
    private static func probe(address: String, strategy: ProbeStrategy) async -> (HealthState, String?) {
        guard let url = URL(string: address), let host = url.host else {
            return (.unreachable, "地址解析失败")
        }
        switch strategy {
        case .http:
            return await probeHTTP(url: url)
        case .tcp:
            let port = UInt16(url.port ?? (url.scheme == "https" ? 443 : 80))
            let reachable = await probeTCP(host: host, port: port)
            return (ConnectionHealthPolicy.summarize(reachable: reachable, rttMs: nil),
                    reachable ? nil : "TCP \(host):\(port) 连接失败")
        case .none:
            return (.unreachable, "离线")
        }
    }

    /// HEAD 请求测往返时延。用 HEAD 而不是 GET：不下载正文，流量最小。
    private static func probeHTTP(url: URL) async -> (HealthState, String?) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = httpTimeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let started = Date()
        do {
            _ = try await URLSession.shared.data(for: request)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            return (ConnectionHealthPolicy.summarize(reachable: true, rttMs: ms), nil)
        } catch {
            // 把 NSError 的 code 带出来：-1001 超时 / -1004 连不上 / -1022 ATS，
            // 这三者修法完全不同，只显示「不可达」没法判断。
            let ns = error as NSError
            NSLog("DSH_PROBE %@ -> %@ \(ns.domain) \(ns.code): \(ns.localizedDescription)", url.absoluteString)
            return (.unreachable, "\(ns.domain) \(ns.code)")
        }
    }

    /// 只建 TCP 连接再断。约 0.2 KB，是蜂窝场景的省流量方案。
    private static func probeTCP(host: String, port: UInt16) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        return await withCheckedContinuation { continuation in
            var finished = false
            let finish: (Bool) -> Void = { value in
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(true)
                case .failed, .cancelled:
                    finish(false)
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue(label: "dsh.endpoint-probe.tcp"))
            DispatchQueue.global().asyncAfter(deadline: .now() + tcpTimeout) {
                finish(false)
            }
        }
    }
}
