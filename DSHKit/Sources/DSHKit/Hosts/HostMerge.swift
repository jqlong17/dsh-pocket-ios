import Foundation

/// 合并「同一台机器却分成多台主机」的纯逻辑。
///
/// 为什么会分叉：新地址连上后如果能读到机器名，应该并进已有机主；
/// 早于机器名机制创建的主机 `machine` 是 nil，匹配不上就新建了一台。
/// 之后一旦两条主机都带上同一个机器名，就该把它们合回去（2026-11-25 实测：
/// 同一台 Mac 因 Cloudflare 地址被拆成了「DSH 1 mac」和「DSH 2」）。
public enum HostMerge {
    /// 找出机器名相同的下标分组（只返回 ≥2 台的组）。
    ///
    /// - 机器名为 nil/空串的不参与（宁可多一台，也不能把两台不同机器并掉）。
    public static func duplicateGroups(machines: [String?]) -> [[Int]] {
        var buckets: [String: [Int]] = [:]
        for (index, machine) in machines.enumerated() {
            guard let machine, !machine.isEmpty else { continue }
            buckets[machine, default: []].append(index)
        }
        return buckets.values.filter { $0.count >= 2 }.map { $0.sorted() }.sorted { $0[0] < $1[0] }
    }

    /// 合并后保留哪一台：优先当前连接的那台，否则最近使用的那台。
    public static func keeper(in group: [Int], currentIndex: Int?, lastUsedAt: [Double]) -> Int {
        if let currentIndex, group.contains(currentIndex) { return currentIndex }
        return group.max { lhs, rhs in
            let l = lhs < lastUsedAt.count ? lastUsedAt[lhs] : 0
            let r = rhs < lastUsedAt.count ? lastUsedAt[rhs] : 0
            return l < r
        } ?? group[0]
    }
}
