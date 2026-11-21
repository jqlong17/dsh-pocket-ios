import Foundation

/// 当前网络类型。只区分「要不要为流量精打细算」这一件事。
public enum NetworkClass: Sendable, Equatable {
    case wifi
    case cellular
    case other
}

/// 一次健康探测用哪种方式。
public enum ProbeStrategy: Sendable, Equatable {
    /// 发一个 HEAD 请求：能拿到 RTT，但每次要重做 TLS 握手（HTTPS 约 5 KB）。
    case http
    /// 只建 TCP 连接再断开：约 0.2 KB，但只能判断端口通不通。
    case tcp
    /// 不探测（例如完全离线）。
    case none
}

/// 一条地址的探测结论。
public enum HealthState: Equatable, Sendable {
    /// 连不上。UI 要明确写出来，而不是沉默。
    case unreachable
    /// 可达；`rttMs` 为 nil 表示只做了 TCP 探测、没测到往返时延。
    case reachable(rttMs: Int?)
}

/// 探测策略与结论归纳。纯判断，无网络、无 UI，可直接单测。
public enum ConnectionHealthPolicy {
    /// Wi-Fi 下用 HTTP（流量免费，且能测 RTT）；
    /// 蜂窝下只做 TCP —— HTTPS 每次要重做 TLS 握手，60 秒一轮会吃掉几百 MB/月。
    public static func strategy(for network: NetworkClass) -> ProbeStrategy {
        switch network {
        case .wifi: return .http
        // 蜂窝与「未知」都只做 TCP。
        // 未知用 TCP 而不是直接跳过：NWPathMonitor 首次回调前 `networkClass` 还是
        // `.other`，若返回 none 会让所有地址恒被标成不可达（实测踩过）。
        // 离线时 TCP 自己也会失败，结论仍然正确，代价只有 0.2 KB。
        case .cellular, .other: return .tcp
        }
    }

    /// 该不该探测这条地址。
    ///
    /// 规则：只探**用户保存过的**地址。理由：
    /// - 没保存的地址用户压根不会切过去，探测是纯浪费；
    /// - 保存列表本身有配额（局域网 3 / 公网 5），天然限制了并发数。
    public static func shouldProbe(address: String, saved: [String]) -> Bool {
        guard !address.isEmpty else { return false }
        return saved.contains(address)
    }

    /// 把一次探测结果归纳成展示状态。
    ///
    /// 注意 `rttMs` 只在 HTTP 探测时才有意义：TCP 探测只返回「通/不通」。
    public static func summarize(reachable: Bool, rttMs: Int?) -> HealthState {
        guard reachable else { return .unreachable }
        // 负数或极大值都当成「没测到」，避免显示 -1ms 这种噪音。
        if let rttMs, rttMs > 0, rttMs < 60_000 {
            return .reachable(rttMs: rttMs)
        }
        return .reachable(rttMs: nil)
    }
}
