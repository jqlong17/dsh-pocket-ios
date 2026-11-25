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

    /// 并发探测一组地址，返回第一个可用的（Happy Eyeballs 思路）。
    ///
    /// 为什么不再串行：以前切 host 是「逐条探 + 失败再换票 + 再探」，
    /// 每条都要等默认超时；局域网不通时要等几十秒，界面就像卡住（2026-11-25 反馈）。
    /// 现在各地址同时探，谁先通就用谁，单条探针 3 秒超时。
    func firstReachableEndpoint(among endpoints: [SavedEndpoint], timeout: TimeInterval = 3) async -> SavedEndpoint? {
        await withTaskGroup(of: (SavedEndpoint, Bool).self) { group in
            for endpoint in endpoints {
                group.addTask { @MainActor in
                    guard let url = try? Self.serverURL(from: endpoint.address) else { return (endpoint, false) }
                    let started = Date()
                    // 局域网要么毫秒级回应，要么根本不在这个网里：给它更短的超时，
                    // 免得在外面时白等满 3 秒（2026-11-25 反馈切 Tailscale 要 5 秒）。
                    let effective = endpoint.kind == .lan ? min(timeout, 1.2) : timeout
                    let ok = await self.probeSessionsFast(at: url, timeout: effective)
                    let ms = Int(Date().timeIntervalSince(started) * 1000)
                    // 计时落盘：切换快不快，看这几行就够（DiagFileLog 可 devicectl 拷出）。
                    DiagFileLog.log("probe \(endpoint.kind.label) ok=\(ok) \(ms)ms")
                    return (endpoint, ok)
                }
            }
            for await (endpoint, ok) in group {
                if ok {
                    group.cancelAll()
                    return endpoint
                }
            }
            return nil
        }
    }

    /// 带超时的会话探测：用「任务竞速」而不是改 URLSession 配置，
    /// 因为 DSHClient 的传输层不接受自定义 session，而默认超时太长（切换场景不需要等）。
    func probeSessionsFast(at url: URL, timeout: TimeInterval) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await self.probeSessions(at: url) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}
