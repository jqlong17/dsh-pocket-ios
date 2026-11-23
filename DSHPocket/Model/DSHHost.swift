// DSHHost

import Foundation

/// 一台 DSH 主机。
///
/// 为什么需要这一层：用户脑子里是「一台机器」，而不是「一串地址」。
/// 同一台机器常有多个地址（家里局域网、公司局域网、Tailscale、Cloudflare），
/// 而「切换」的语义其实是**换一台机器**，不是换一条地址。
///
/// 所以把身份和可达性分开：
/// - `DSHHost` 是身份（有名字、可改名、可删除）；
/// - `endpoints` 是它现在的可达路径，由自动选路挑最优的一条。
struct DSHHost: Codable, Identifiable, Hashable {
    /// 稳定标识：首次出现时生成，之后不随地址变化。
    var id: String
    /// 用户看得见的名字：「Mac」「阿里云」。可改。
    var name: String
    /// 这台机器的可达地址，按最近使用排序维护。
    var endpoints: [SavedEndpoint]
    var lastUsedAt: Double
    /// 插件报出的 hostname。用来判断「这条新地址是不是同一台机器」。
    /// 拿不到就是 nil——那时新地址会自成一台主机，由用户决定要不要合并。
    var machine: String?

    var displayName: String { name.isEmpty ? endpoints.first?.displayName ?? "DSH" : name }

    /// 最近用过的那条地址（探针/自动选路之外的兜底）。
    var preferredEndpoint: SavedEndpoint? {
        endpoints.max { $0.lastUsedAt < $1.lastUsedAt }
    }
}

extension DSHHost {
    /// 从扁平的地址列表迁移出主机列表。
    ///
    /// 规则（对应 spec 的迁移一节）：
    /// 1. 有 `machine` 的按 machine 归并——那是同一台机器；
    /// 2. 没有 `machine` 的各自成一台（宁可多，也不能把两台并成一台）；
    /// 3. 名字优先沿用用户改过的 `label`，否则给 `DSH n`。
    static func migrate(from endpoints: [SavedEndpoint]) -> [DSHHost] {
        var groups: [String: [SavedEndpoint]] = [:]
        var anonymous: [[SavedEndpoint]] = []
        for endpoint in endpoints {
            if let machine = endpoint.machine, !machine.isEmpty {
                groups[machine, default: []].append(endpoint)
            } else {
                // 没有机器名：不能猜，一条一台。
                anonymous.append([endpoint])
            }
        }

        var usedNames = Set<String>()
        var hosts: [DSHHost] = []

        // 有机器名的一组一台。
        for (machine, list) in groups.sorted(by: { $0.key < $1.key }) {
            let name = list.compactMap(\.label).first ?? nextName(used: &usedNames)
            usedNames.insert(name)
            hosts.append(DSHHost(
                id: UUID().uuidString,
                name: name,
                endpoints: list.sorted { $0.lastUsedAt > $1.lastUsedAt },
                lastUsedAt: list.map(\.lastUsedAt).max() ?? 0,
                machine: machine
            ))
        }
        // 没有机器名的：一条一台。
        for list in anonymous.sorted(by: { ($0.map(\.lastUsedAt).max() ?? 0) > ($1.map(\.lastUsedAt).max() ?? 0) }) {
            let name = list.compactMap(\.label).first ?? nextName(used: &usedNames)
            usedNames.insert(name)
            hosts.append(DSHHost(
                id: UUID().uuidString,
                name: name,
                endpoints: list,
                lastUsedAt: list.map(\.lastUsedAt).max() ?? 0,
                machine: nil
            ))
        }
        // 当前最常用的排前面：用户大多数时候只有一两台，顺序影响点击距离。
        return hosts.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    private static func nextName(used: inout Set<String>) -> String {
        var n = 1
        while used.contains("DSH \(n)") { n += 1 }
        return "DSH \(n)"
    }
}
