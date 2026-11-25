// ConnectionModel+HostMerging
//
// 「这些地址属于哪台机器」与「地址怎么存」是两件事：后者留在
// ConnectionModel+Endpoints，前者（机器名、重复主机合并）放这里。
// 拆出来的直接原因：原文件超过架构检查的 600 行上限（2026-11-25）。

import Foundation
import DSHKit

extension ConnectionModel {
    /// 从响应头读机器名（插件每个响应都带 `x-dsh-machine`）。
    ///
    /// **必须在 `persistConnectedState()` 之前调用**：主机分组按机器名归并，
    /// 晚一步就会先建出一台新主机，于是同一台 DSH 的局域网和 Cloudflare 地址
    /// 被拆成「DSH 1」「DSH 2」（2026-11-25 用户实测）。
    @MainActor
    func captureMachineName(from response: URLResponse?) {
        guard let http = response as? HTTPURLResponse,
              let name = http.value(forHTTPHeaderField: "x-dsh-machine"),
              !name.isEmpty else { return }
        currentMachineName = name
    }

    /// 把「同一台机器被拆成多台主机」的情况合回去。
    ///
    /// 触发场景：早于机器名机制创建的主机 `machine` 是 nil，新地址匹配不上就新建了一台；
    /// 之后两台都带上同一个机器名，这里把它们合成一台（保留当前连接那台）。
    func mergeDuplicateMachines() {
        let groups = HostMerge.duplicateGroups(machines: hosts.map(\.machine))
        guard !groups.isEmpty else { return }
        let currentIndex = hosts.firstIndex { $0.id == currentHostId }
        let lastUsed = hosts.map(\.lastUsedAt)
        // 从后往前删，避免下标失效
        for group in groups.reversed() {
            let keeper = HostMerge.keeper(in: group, currentIndex: currentIndex, lastUsedAt: lastUsed)
            var merged = hosts[keeper].endpoints
            for index in group where index != keeper {
                for endpoint in hosts[index].endpoints where !merged.contains(where: { $0.address == endpoint.address }) {
                    merged.append(endpoint)
                }
                hosts[keeper].lastUsedAt = max(hosts[keeper].lastUsedAt, hosts[index].lastUsedAt)
            }
            hosts[keeper].endpoints = merged
            if let currentIndex, group.contains(currentIndex) { currentHostId = hosts[keeper].id }
            for index in group.sorted(by: >) where index != keeper { hosts.remove(at: index) }
            recordDiagnostic("合并了同机器的主机：\(hosts.first(where: { $0.endpoints == merged })?.name ?? "?")")
        }
    }
}
