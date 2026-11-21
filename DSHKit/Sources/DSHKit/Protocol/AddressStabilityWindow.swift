import Foundation

/// 稳定性评级。阈值按「最近窗口里有多少采样是健康状态」划。
public enum StabilityGrade: Equatable, Sendable {
    /// 样本太少，不下结论。
    case unknown
    /// 全部健康。
    case stable
    /// 健康占比 ≥ 80%：偶尔抖一下。
    case occasional
    /// 健康占比 ≥ 50%：会明显打断使用。
    case unstable
    /// 健康占比 < 50%：基本不能用。
    case poor
}

/// 一条地址的稳定性摘要。
public struct AddressStability: Equatable, Sendable {
    public let samples: Int
    public let healthy: Int

    /// 健康占比 0...1。空窗口返回 0。
    public var ratio: Double {
        guard samples > 0 else { return 0 }
        return Double(healthy) / Double(samples)
    }

    /// 少于 3 个样本时判 `unknown`：一次抖动就下结论会误导用户。
    public var grade: StabilityGrade {
        guard samples >= 3 else { return .unknown }
        if healthy == samples { return .stable }
        if ratio >= 0.8 { return .occasional }
        if ratio >= 0.5 { return .unstable }
        return .poor
    }

    public static let empty = AddressStability(samples: 0, healthy: 0)
}

/// 按地址分别累积健康采样的滚动窗口。
///
/// 为什么必须按地址分开（2026-11-21 用户反馈）：
/// 全局窗口在用户切换地址后会把两条路的数据混在一起，
/// 于是「失败 2 次」到底是局域网还是 Tailscale 造成的，永远说不清。
public struct AddressStabilityWindow {
    /// 每个地址最多保留多少条采样。10 秒采样 × 30 = 最近 5 分钟。
    public let capacity: Int
    private var samples: [String: [Bool]] = [:]

    public init(capacity: Int = 30) {
        self.capacity = max(1, capacity)
    }

    /// 记一次采样。`connected == true` 表示该地址当时是健康的。
    public mutating func record(address: String, connected: Bool) {
        guard !address.isEmpty else { return }
        var list = samples[address, default: []]
        list.append(connected)
        if list.count > capacity {
            list.removeFirst(list.count - capacity)
        }
        samples[address] = list
    }

    /// 某地址的稳定性摘要。
    public func stability(for address: String) -> AddressStability {
        guard let list = samples[address], !list.isEmpty else { return .empty }
        return AddressStability(samples: list.count, healthy: list.filter { $0 }.count)
    }

    /// 只保留给定的这些地址，其余丢弃（地址被用户删掉后不再占用内存）。
    public mutating func retain(addresses: Set<String>) {
        samples = samples.filter { addresses.contains($0.key) }
    }
}
