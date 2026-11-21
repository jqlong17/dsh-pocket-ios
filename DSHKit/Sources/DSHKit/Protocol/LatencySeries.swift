import Foundation

/// 一条地址最近若干次探测的时延序列。
///
/// 为什么不用「最近 N 秒」：正常模式 60 秒一轮，1 分钟只有 1 个点；
/// 测试模式 10 秒一轮，1 分钟 6 个点。同一个时间窗在两种模式下含义完全不同，
/// 按「最近 N 次」才稳定可比。
public struct LatencySeries: Equatable, Sendable {
    /// 每次探测结果的毫秒数；`nil` 表示那次探测失败（不可达）。
    public private(set) var samples: [Int?] = []
    /// 最多保留多少个点。20 点在设置页里画出来已经足够密。
    public let capacity: Int

    public init(capacity: Int = 20) {
        self.capacity = max(1, capacity)
    }

    public mutating func record(ms: Int?) {
        // 负数/异常值当失败处理，避免曲线出现 -1 这种尖刺。
        let clean = (ms ?? -1) > 0 ? ms : nil
        samples.append(clean)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    /// 有数据的探测次数（不含失败点）。
    public var reachableCount: Int { samples.compactMap { $0 }.count }

    /// 失败次数。UI 用来画红点。
    public var failureCount: Int { samples.filter { $0 == nil }.count }

    /// 序列里最后一个值（最近一次）。
    public var latestMs: Int? { samples.last ?? nil }

    public var minimumMs: Int? { samples.compactMap { $0 }.min() }
    public var maximumMs: Int? { samples.compactMap { $0 }.max() }

    /// 曲线的纵轴范围。没有任何成功样本时返回 nil（UI 不画线）。
    /// 上下各留 1 的余量，避免全等值时曲线贴边。
    public var plotRange: ClosedRange<Double>? {
        let values = samples.compactMap { $0 }
        guard let lo = values.min(), let hi = values.max() else { return nil }
        if lo == hi {
            let center = Double(lo)
            return (center - 1)...(center + 1)
        }
        return Double(lo)...Double(hi)
    }

    /// 失败点的索引（用于在曲线上标红）。
    public var failureIndices: [Int] {
        samples.enumerated().compactMap { $0.element == nil ? $0.offset : nil }
    }
}
