// 已保存的服务器地址

import SwiftUI
import Security
import DSHKit
import VisionKit
import AVFoundation
import Observation
import PhotosUI
import UIKit
import Photos
import os
import AudioToolbox
import ImageIO
import UserNotifications

extension ConnectionModel {

    static func endpointKind(of address: String) -> SavedEndpoint.Kind {
        SavedEndpoint.Kind(DSHEndpointPolicy.kind(of: address))
    }

    /// 读主机列表；没有就以旧地址列表迁移一次。
    func loadSavedEndpoints() {
        if let data = UserDefaults.standard.data(forKey: Self.hostsKey),
           let list = try? JSONDecoder().decode([DSHHost].self, from: data),
           !list.isEmpty {
            hosts = list
        // 启动就把「同一台机器被拆成多台」的合回去（老数据也会有）
        mergeDuplicateMachines()
        } else if let data = UserDefaults.standard.data(forKey: Self.savedEndpointsKey),
                  let list = try? JSONDecoder().decode([SavedEndpoint].self, from: data),
                  !list.isEmpty {
            // 迁移：有机器名的按机器名归并，没有的各成一台。
            // 旧键不删——迁移结果不对时还能回退重跑。
            hosts = DSHHost.migrate(from: Self.dedupEndpoints(list))
        // 启动就把「同一台机器被拆成多台」的合回去（老数据也会有）
        mergeDuplicateMachines()
            persistHosts()
            recordDiagnostic("迁移为 \(hosts.count) 台主机（原 \(list.count) 条地址）")
        }
        if currentHostId == nil {
            // 先认「上次选中的主机」（显式持久化），再退回「地址反推」。
            let persisted = UserDefaults.standard.string(forKey: Self.currentHostIdKey)
            currentHostId = hosts.first { $0.id == persisted }?.id
                ?? hosts.first { host in
                    host.endpoints.contains { $0.address == connection.serverAddress }
                }?.id
                ?? hosts.first?.id
        }
        // 启动时若「上次选中的主机」不是当前地址所属的那台，先把地址挪过去。
        // 这样 restoreConnection 会先试它；失败后仍会退回上次连成功的地址（见 restore 的错误路径）。
        if let id = currentHostId,
           let host = hosts.first(where: { $0.id == id }),
           !host.endpoints.contains(where: { $0.address == connection.serverAddress }),
           let preferred = Self.preferredEndpointIn(host) {
            connection.serverAddress = preferred.address
            recordDiagnostic("启动优先恢复上次选中的主机：\(host.name)")
        }
        seedServerEndpointIfNeeded()
    }

    /// 仅 DEBUG 下播种开发机地址，且地址来自启动环境变量（DSH_DEV_SERVER），
    /// 代码里不留任何公网地址，正式包更不会写入 UserDefaults。
    /// 用户已经手工保存的端点一律保留。
    func seedServerEndpointIfNeeded() {
#if DEBUG
        let address = (ProcessInfo.processInfo.environment["DSH_DEV_SERVER"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        let existing = savedEndpoints.map(\.address)
        guard DSHEndpointPolicy.shouldAutoSeedDevelopmentEndpoint(
            isDebugBuild: true,
            existingAddresses: existing,
            developmentAddress: address
        ) else { return }
        recordEndpoint(address)
#endif
    }

    /// 去重 + 配额交给 DSHKit；这里只做模型映射。
    static func dedupEndpoints(_ list: [SavedEndpoint]) -> [SavedEndpoint] {
        let records = list.map {
            DSHSavedEndpointRecord(address: $0.address, kind: $0.kind.policyKind, lastUsedAt: $0.lastUsedAt, label: $0.label)
        }
        return DSHEndpointPolicy.dedup(records).map {
            SavedEndpoint(address: $0.address, kind: SavedEndpoint.Kind($0.kind), lastUsedAt: $0.lastUsedAt, label: $0.label)
        }
    }

    /// 连接成功后记录这条地址属于哪台主机。
    ///
    /// 归属顺序（先确定、后猜测）：
    /// 1. 已有主机的某个地址就是它 → 更新使用时间；
    /// 2. 插件报过机器名，且已有主机是同名机器 → 把这条地址挂进那台；
    /// 3. 都不匹配 → 新建一台主机，默认名 DSH n。
    func recordEndpoint(_ address: String) {
        guard let url = try? Self.serverURL(from: address) else { return }
        // 存的是去参数后的地址：配对 token 只用于当次登录，不写进地址列表。
        let normalized = DSHURL.baseAddress(url)
        let now = Date().timeIntervalSince1970
        let machine = currentMachineName

        if let hi = hosts.firstIndex(where: { $0.endpoints.contains { $0.address == normalized } }) {
            if let ei = hosts[hi].endpoints.firstIndex(where: { $0.address == normalized }) {
                hosts[hi].endpoints[ei].lastUsedAt = now
            }
            hosts[hi].lastUsedAt = now
            if let machine, !machine.isEmpty { hosts[hi].machine = machine }
            currentHostId = hosts[hi].id
            persistHosts()
            persistCurrentHostId()
            return
        }

        if let machine, !machine.isEmpty,
           let hi = hosts.firstIndex(where: { $0.machine == machine }) {
            hosts[hi].endpoints.append(SavedEndpoint(address: normalized,
                                                    kind: Self.endpointKind(of: normalized),
                                                    lastUsedAt: now))
            hosts[hi].lastUsedAt = now
            currentHostId = hosts[hi].id
            persistHosts()
            persistCurrentHostId()
            recordDiagnostic("地址归并到已有主机：\(machine)")
            return
        }

        let host = DSHHost(id: UUID().uuidString,
                           name: Self.nextHostName(hosts),
                           endpoints: [SavedEndpoint(address: normalized,
                                                     kind: Self.endpointKind(of: normalized),
                                                     lastUsedAt: now)],
                           lastUsedAt: now,
                           machine: machine)
        hosts.append(host)
        currentHostId = host.id
        mergeDuplicateMachines()
        persistHosts()
        persistCurrentHostId()
    }


    /// 生成主机默认名：DSH 1、DSH 2……（避开已占用的名字）。
    static func nextHostName(_ hosts: [DSHHost]) -> String {
        // 逻辑抽到 DSHKit（有测试）：只比对完全相等的名字会漏掉「DSH 2 阿里云」，
        // 用户改名后新机器又拿到 DSH 2，列表里出现两台同名的（2026-11-25 实测）。
        HostNaming.nextName(existing: hosts.map(\.name))
    }

    /// 取当前这台 DSH 的机器名（插件 tailscale.status 里的 machineName）。
    ///
    /// 为什么要这一步：设置里的连接列表只是一串地址，而同一台机器常有多个地址
    /// （局域网 + Tailscale）。没有机器名就只能平铺，用户看不出「这两条是同一台」。
    /// 取不到就保持 nil——那种情况下界面按地址各自成组，不会错，只是不合并。
    @MainActor
    func refreshMachineName() async {
        guard let base = try? Self.serverURL(from: connection.serverAddress) else { return }
        var request = URLRequest(url: base.appending(path: "dsh-pocket-ios/tailscale.status"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = true
        request.timeoutInterval = 8
        let envelope: [String: Any] = [
            "type": "client-request",
            "rpcId": UUID().uuidString,
            "method": "tailscale.status",
            "payload": ["args": [:] as [String: Any]],
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: envelope) else { return }
        request.httpBody = body
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let value = result["value"] as? [String: Any],
              let name = value["machineName"] as? String,
              !name.isEmpty else { return }
        currentMachineName = name
        // 回写一遍：把机器名补到刚存下的那条地址上。
        recordEndpoint(connection.serverAddress)
    }

    /// 给还没有名字的旧地址补上默认名（DSH 1、DSH 2…）。
    ///
    /// 为什么必须补：分组是按名字来的，没有名字时会退回「局域网 / 公网」这种类型名，
    /// 于是**两条不同机器的局域网地址会被错并成一组**。补上唯一名字才不会并错。
    /// 只在用户没改过名的地址上动手，改过的一律不碰。
    /// 用 session/list 的最新 running 校验一次（只在没有实时 turn 事件时生效）。
    @MainActor
    func refreshRunningState(for sessionId: String) async {
        guard activeConversation?.sessionId == sessionId,
              activeConversation?.liveTurnEventsSeen == false,
              let fresh = try? await fetchSessions(),
              let latest = fresh.first(where: { $0.sessionId == sessionId }) else { return }
        if !latest.running {
            isTurnRunning = false
            turnStartedAt = nil
            recordDiagnostic("运行状态校验：会话已结束")
        } else {
            recordDiagnostic("运行状态校验：仍在运行")
        }
    }

    /// 把回复切成有序片段：文本段与图片段交替，图片按 Markdown 中的原位置渲染。
    /// 切分逻辑在 DSHKit（纯逻辑、可单测），这里只提供「怎么把地址变成 URL」。
    func markdownSegments(_ markdown: String) -> [MarkdownSegment] {
        MarkdownSegments.split(markdown) { [weak self] destination in
            self?.markdownImageURL(for: destination)
        }.map { segment in
            switch segment {
            case .text(let text): return MarkdownSegment.text(text)
            case .image(let url, let caption): return MarkdownSegment.image(url, caption: caption)
            }
        }
    }

    func markdownImageURL(for destination: String) -> URL? {
        if let url = URL(string: destination),
           let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            return url
        }
        guard let base = try? Self.serverURL(from: connection.serverAddress) else { return nil }
        var raw = destination.removingPercentEncoding ?? destination
        if raw.hasPrefix("file://") { raw = String(raw.dropFirst("file://".count)) }
        else if raw.hasPrefix("file:") { raw = String(raw.dropFirst("file:".count)) }
        guard !raw.isEmpty else { return nil }
        let absolute: String
        if raw.hasPrefix("/") {
            absolute = raw
        } else if let cwd = sessionStore.selected?.cwd, cwd.hasPrefix("/") {
            absolute = URL(fileURLWithPath: cwd).appendingPathComponent(raw).standardized.path
        } else {
            return nil
        }
        var components = URLComponents(url: base.appending(path: "api/file"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "path", value: absolute)]
        return components?.url
    }

    /// 会话列表的 updatedAt 可能是毫秒或秒，统一成 Date。
    static func dateFromSessionUpdatedAt(_ value: TimeInterval) -> Date {
        let seconds = value > 10_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }

    /// 给已保存地址设置/清除自定义标签（如「公司」「家」）。
    /// 删除一条已保存的连接（只删记录，不影响当前正在使用的地址）。
    @MainActor
    func removeEndpoint(_ address: String) {
        if let hi = hosts.firstIndex(where: { $0.endpoints.contains { $0.address == address } }) {
            hosts[hi].endpoints.removeAll { $0.address == address }
            // 一条地址都不剩的主机就不该留在列表里。
            if hosts[hi].endpoints.isEmpty {
                if currentHostId == hosts[hi].id { currentHostId = nil }
                hosts.remove(at: hi)
            }
            persistHosts()
        }
        // 删掉的正是当前这台电脑：把 Keychain 里的地址与登录 cookie 一起清掉，
        // 否则下次启动又会凭旧凭证自动连回来——用户会以为「删了还在」。
        if address == connection.serverAddress {
            ConnectionVault.clear(address: connection.serverAddress)
            UserDefaults.standard.removeObject(forKey: Self.savedServerAddressKey)
            connection.pin = ""
            PinKeychain.clear()
        }
    }

    /// 改的是**主机名**，不是地址标签。
    ///
    /// 语义修正：以前这里改 `endpoint.label`，导致「改名」实际只改了某条地址，
    /// 同一台机器的另一条地址还是旧名字，于是分组怎么都合不上。
    func renameEndpoint(_ address: String, label: String?) {
        guard let hi = hosts.firstIndex(where: { $0.endpoints.contains { $0.address == address } }) else { return }
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            hosts[hi].name = trimmed
            persistHosts()
        }
    }

    /// **实际正在连的那台主机**（由 `connection.serverAddress` 反推）。
    ///
    /// 为什么需要它：`currentHostId` 表示「用户上次选的主机」，是偏好；
    /// 而实际连接可能因为回滚/兜底落到另一台（例如选中的阿里云连不上、
    /// 自动退回 Mac）。两者一旦不一致，界面会显示「已连接 DSH 1」，
    /// 会话列表却是 DSH 2 的内容（2026-11-24 真机反馈）。
    /// 所以凡是「显示当前连的是谁」，一律用这个；`currentHostId` 只用于启动时优先尝试。
    var connectedHost: DSHHost? {
        hosts.first { host in
            host.endpoints.contains { $0.address == connection.serverAddress }
        }
    }

    /// 让「上次选中的主机」跟随实际连接。
    ///
    /// 连接成功后调用：偏好应反映现实，否则下次启动会优先去试一台并不是上次真正在用的机器。
    func syncCurrentHostIdWithConnection() {
        guard let host = connectedHost, currentHostId != host.id else { return }
        currentHostId = host.id
        persistCurrentHostId()
    }

    /// 持久化「上次选中的主机」。
    func persistCurrentHostId() {
        if let id = currentHostId {
            UserDefaults.standard.set(id, forKey: Self.currentHostIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.currentHostIdKey)
        }
    }

    /// 主机内优先用哪条地址：局域网优先，其次最近使用。
    /// 与 `switchHost` 的挑选规则保持一致，避免「启动选的」和「切换选的」不是同一条。
    static func preferredEndpointIn(_ host: DSHHost) -> SavedEndpoint? {
        host.endpoints.sorted { a, b in
            if (a.kind == .lan) != (b.kind == .lan) { return a.kind == .lan }
            return a.lastUsedAt > b.lastUsedAt
        }.first
    }

    /// 改主机名（设置页的铅笔走这里）。
    @MainActor
    func renameHost(id: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = hosts.firstIndex(where: { $0.id == id }) else { return }
        hosts[index].name = trimmed
        persistHosts()
    }

    /// 删掉整台主机（连同它的所有地址）。
    @MainActor
    func removeHost(id: String) {
        guard let host = hosts.first(where: { $0.id == id }) else { return }
        let wasCurrent = (host.id == currentHostId)
        let removingCurrentAddress = host.endpoints.contains { $0.address == connection.serverAddress }

        // 整台删除：**每一条**地址的凭证和探测历史都要清。
        // 只清「当前正在用的那条」会留下残留——重新添加同名主机时可能带出早就删掉的
        // 局域网地址，或拿着旧 cookie 得到 401，表现就是「切过去连不上」（2026-11-25 反馈）。
        for endpoint in host.endpoints {
            ConnectionVault.clearEndpointCredentials(address: endpoint.address)
            probeLatency.removeValue(forKey: endpoint.address)
        }
        if removingCurrentAddress {
            ConnectionVault.clear(address: connection.serverAddress)
            UserDefaults.standard.removeObject(forKey: Self.savedServerAddressKey)
        }

        hosts.removeAll { $0.id == id }
        if wasCurrent {
            // 删的是当前主机：必须真的断开，否则会停在「已连接但没有主机」的状态。
            disconnect()
            connection.serverAddress = ""
        }
        if currentHostId == id { currentHostId = hosts.first?.id }
        persistHosts()
        persistCurrentHostId()
    }

    /// 按主机切换：在它的地址里挑最优的一条（局域网优先），逐个试，第一个成功即完成。
    @MainActor


    func switchHost(to hostId: String) async -> Bool {
        guard let host = hosts.first(where: { $0.id == hostId }) else { return false }
        if host.id == currentHostId, connection.isConnected { return true }
        let switchStarted = Date()
        DiagFileLog.log("switch begin host=\(host.name) endpoints=\(host.endpoints.count)")
        // 先并发探一遍：哪条通就用哪条，避免在不通的地址上等超时。
        for endpoint in host.endpoints {
            if let url = try? Self.serverURL(from: endpoint.address) {
                ConnectionVault.restoreAuthCookies(to: url, address: endpoint.address)
            }
        }
        if let fast = await firstReachableEndpoint(among: host.endpoints) {
            DiagFileLog.log("switch picked \(fast.kind.label) after \(Int(Date().timeIntervalSince(switchStarted) * 1000))ms")
            if await switchConnection(to: fast.address, verified: true) {
                DiagFileLog.log("switch done in \(Int(Date().timeIntervalSince(switchStarted) * 1000))ms")
                currentHostId = hostId
                persistHosts()
                persistCurrentHostId()
                return true
            }
        }
        return false
    }

    /// 手动切换到某个已保存地址（失败时回滚，保持原连接）。
    @MainActor
    func switchToEndpoint(_ endpoint: SavedEndpoint) async {
        guard !isDemoMode else { return }
        let previous = connection.serverAddress
        connection.serverAddress = endpoint.address
        connection.errorMessage = nil
        do {
            sessionStore.sessions = try await fetchSessions()
            connection.isConnected = true
            recordEndpoint(endpoint.address)
            syncCurrentHostIdWithConnection()
            recordDiagnostic("切换连接：\(endpoint.kind.label) \(DSHURL.redactedAddress(endpoint.address))")
        } catch {
            connection.serverAddress = previous
            // 换票也失败：先别急着报错——可能只是「这条路在这个网络里不通」。
            // 冷启动时上面只试了「上次用的那一条」，那条如果是公网而人正在家里/公司，
            // 必然失败并退回连接页（2026-11-23 反馈「每次都是公网」）。
            if await restoreFallbackRoute() { return }
            // ③ 仍失败：退回「上次连成功的那台」。
            // 场景：上次选中的主机（比如阿里云）现在彻底不通，而上次连成功的 Mac 还在。
            // 没有这一步，用户会停在连接页——而他其实有一台能用的机器。
            if let lastGood = UserDefaults.standard.string(forKey: Self.savedServerAddressKey),
               lastGood != connection.serverAddress,
               hosts.contains(where: { $0.endpoints.contains { $0.address == lastGood } }) {
                recordDiagnostic("仍连不上，退回上次连接成功的地址：\(DSHURL.redactedAddress(lastGood))")
                connection.serverAddress = lastGood
                connection.errorMessage = nil
                await connect()
                if connection.isConnected { return }
            }
            applyConnectError(error)
            if connection.isConnected { recordDiagnostic("切换连接失败，已回滚：\(error.localizedDescription)") }
        }
    }

    @MainActor
    func restoreConnection() async {
        // 所有退出路径都必须标记「恢复已结束」，否则视图会停在占位页（永久白屏）。
        // 这里用 defer：本函数有 5 条提前 return，手写必然漏掉一条。
        defer { connection.hasFinishedRestore = true }
        if isDemoMode { return }
#if DEBUG
        if DebugLaunch.showConnect { return }
        if DebugLaunch.demoMode { startDemoMode(); return }
        if let server = DebugLaunch.server {
            connection.serverAddress = server
            if let pin = DebugLaunch.pin { connection.pin = pin }
            recordDiagnostic("Debug 自动连接：\(DSHURL.redactedAddress(server))")
            await connect()
            return
        }
#endif
        // 地址可能来自 Keychain（重装后沙盒被清），所以不只看 UserDefaults。
        let hasAddress = UserDefaults.standard.string(forKey: Self.savedServerAddressKey) != nil
            || ConnectionVault.loadAddress() != nil
        guard hasAddress, let base = try? Self.serverURL(from: connection.serverAddress) else { return }
        // 恢复登录态：沙盒被清后 cookie 会丢，从 Keychain 放回，避免重新扫码。
        ConnectionVault.restoreAuthCookies(to: base, address: connection.serverAddress)
        do {
            sessionStore.sessions = try await fetchSessions()
            connection.isConnected = true
            connection.errorMessage = nil
            // 普通恢复也要注册 APNs——App 正常启动走的就是这条。
        } catch {
            // cookie 失效（DSH 重启、或重装后沙盒里的 cookie 被清）：
            // 只要 Keychain 里还留着长期设备凭证，就先静默换一张新票再试。
            // 之前这里只 applyConnectError，等于把「免扫码」的能力浪费了——
            // 每次重装 build 用户都得重新扫一次（2026-11-15 反馈）。
            if ConnectionVault.loadDeviceToken(for: connection.serverAddress) != nil, await tryRefreshAuth() {
                do {
                    sessionStore.sessions = try await fetchSessions()
                    connection.isConnected = true
                    connection.errorMessage = nil
                    recordDiagnostic("恢复连接：设备凭证换票成功，免扫码")
                    // 这条 return 以前不落盘、也不同步偏好，导致「实际连的是 A、
                    // 界面显示 B」能一直留到下次启动（2026-11-24 真机反馈）。
                    recordEndpoint(connection.serverAddress)
                    syncCurrentHostIdWithConnection()
                    return
                } catch {
                    // 换票成功但拉会话仍失败，继续走下面的错误上报
                }
            }
            connection.isConnected = false
            applyConnectError(error)
        }
    }

    /// 恢复失败时，换一条已保存的路再试一次。
    ///
    /// 与 `autoRouteIfEnabled` 的分工：
    /// - 那个要求 `connection.isConnected`，是「连上之后优化」；
    /// - 这个是「没连上」时用——正是它的场景，所以不能套用那个 guard。
    ///
    /// 只排除**当前这条**（刚试过并失败），其余仍按「局域网优先 + 延迟最低」挑，
    /// 与手动选路的规则保持一致，避免出现两套不同的偏好。
    /// 切换到另一台机器/另一条地址，**先验证再切**。
    ///
    /// 为什么不直接改地址再 `connect()`：`connect()` 会重置当前会话状态。
    /// 一旦目标不可用（云服务器关机、换了个网络、这台没配对过），
    /// 用户就「原来的连接没了、新的也连不上」，只能重新扫码——
    /// 这正是「切过去失败就卡死在连接页」的由来。
    ///
    /// 所以先用**新地址**独立拉一次会话列表（一次请求同时验证：网络可达、
    /// 登录态有效、DSH 在跑），全部通过才动当前连接。
    /// cookie 由 URLSession 按 host 自动匹配（见 ConnectionVault），不需要也不该
    /// 在这里手动搬凭证。
    @MainActor
    func switchConnection(to address: String, verified: Bool = false) async -> Bool {
        let target = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, target != connection.serverAddress else { return true }
        guard let url = try? Self.serverURL(from: target) else {
            recordDiagnostic("切换失败：地址无法解析 \(DSHURL.redactedAddress(target))")
            return false
        }

        // ① 独立验证，不碰当前连接。
        //
        // 顺序很重要：目标机器的 cookie 多半已经过期（DSH 重启过、或很久没连），
        // 直接探针会 401 → 被判「不可用」。所以先恢复 Keychain 里的 cookie，
        // 401 时再用**目标地址**的设备凭证换一次新票，然后重试。
        // 之前漏了这两步，表现就是「切换永远失败」。
        ConnectionVault.restoreAuthCookies(to: url, address: target)
        // verified=true：调用方（switchHost）刚用并发探测确认过这条通，不必再探一遍。
        // 这一步以前要白等一个 RTT，是切 host 总耗时的一部分（2026-11-25）。
        if !verified {
            let probeStarted = Date()
            if !(await probeSessions(at: url)) {
                guard await tryRefreshAuth(for: target), await probeSessions(at: url) else {
                    recordDiagnostic("切换目标不可用，保持当前连接：\(DSHURL.redactedAddress(target))")
                    return false
                }
            }
            DiagFileLog.log("switch probe(serial) \(Int(Date().timeIntervalSince(probeStarted) * 1000))ms")
        }

        // ② 验证通过，才切
        recordDiagnostic("切换连接：\(DSHURL.redactedAddress(connection.serverAddress)) → \(DSHURL.redactedAddress(target))")
        disconnect()
        connection.serverAddress = target
        connection.errorMessage = nil
        await connect()
        return connection.isConnected
    }

    /// 用指定地址探一次会话列表：能拉到就说明网络、登录态、DSH 三者都正常。
    @MainActor
    func probeSessions(at url: URL) async -> Bool {
        do {
            _ = try await DSHClient(baseURL: url).sessions()
            return true
        } catch {
            recordDiagnostic("探针失败 \(DSHURL.redactedAddress(url.absoluteString))：\(ConnectFailureMessage.diagnosticText(error))")
            return false
        }
    }

    @MainActor
    private func restoreFallbackRoute() async -> Bool {
        // 只在当前主机的地址里挑：跨主机跳转在主机模型下是错的
        let addresses = currentHostEndpoints.map(\.address)
        guard addresses.count > 1 else { return false }
        await probeRunner.probeRound(addresses: addresses)

        let candidates = currentHostEndpoints.compactMap { endpoint -> RouteCandidate? in
            guard endpoint.address != connection.serverAddress else { return nil }
            let kind = DSHEndpointKind(rawValue: Self.endpointKind(of: endpoint.address).rawValue) ?? .custom
            switch probeRunner.results[endpoint.address] {
            case .reachable(let value):
                return RouteCandidate(address: endpoint.address, kind: kind, reachable: true, rttMs: value)
            case .unreachable:
                return RouteCandidate(address: endpoint.address, kind: kind, reachable: false, rttMs: nil)
            case .none:
                return nil    // 还没探测到，不参与选择
            }
        }
        guard let target = RoutePolicy.choose(from: candidates, preference: .lanFirst) else { return false }

        recordDiagnostic("恢复失败，换路重试：\(DSHURL.redactedAddress(target))")
        connection.serverAddress = target
        connection.errorMessage = nil
        await connect()
        return connection.isConnected
    }

    @MainActor
    func disconnect() {
        if isDemoMode { exitDemoMode(); return }
        conversationToken = UUID()
        turnStarts.removeAll()
        turnEnds.removeAll()
        liveTask?.cancel()
        fallbackTask?.cancel()
        liveTask = nil
        for conversation in sessionStore.conversations.values {
            conversation.liveTask?.cancel()
            conversation.fallbackTask?.cancel()
            conversation.coordinatorTask?.cancel()
            if let coordinator = conversation.coordinator { Task { await coordinator.stop() } }
        }
        sessionStore.conversations.removeAll()
        activeConversation = nil
        sessionStore.selected = nil
        sessionStore.sessions = []
        sessionStore.archivedSessionIds = []
        liveConnection = .idle
        connection.isConnected = false
    }
}
