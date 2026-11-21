// 连接、诊断和引用

import SwiftUI
import Security
import Textual
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

    /// 会话规模快照：读模型状态，因此留在模型侧；文本拼装在 Diagnostics。
    @MainActor
    func retainedConversationStats() -> (sessions: Int, messages: Int, textBytes: Int, stepBytes: Int) {
        var messageCount = 0
        var textBytes = 0
        var stepBytes = 0
        for conversation in sessionStore.conversations.values {
            messageCount += conversation.messages.count
            textBytes += conversation.messages.reduce(0) { $0 + $1.text.utf8.count }
            stepBytes += conversation.steps.reduce(0) { $0 + $1.resultText.utf8.count + $1.detail.utf8.count }
        }
        return (sessionStore.conversations.count, messageCount, textBytes, stepBytes)
    }

    @MainActor
    @discardableResult
    func useScannedAddress(_ value: String) -> Bool {
        guard var components = URLComponents(string: value),
            let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
            components.host != nil else {
            // 扫到的不是电脑地址：属于「地址无效」，提示里直接引导再扫一次，所以给重新扫码入口。
            let failure = ConnectFailureMessage.scannedAddressInvalid()
            connection.addressNeedsRescan = failure.needsRescan
            connection.errorMessage = failure.text
            return false
        }
        // 二维码/粘贴的地址可能携带：?token=<DSH 认证 token>（登录后浏览器地址栏），或旧版 ?connection.pin=<密码>。
        if let pairToken = components.queryItems?.first(where: { $0.name == "pair" })?.value,
        !pairToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingPairToken = pairToken
            connection.pin = ""
        } else if let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingLoginToken = token
            connection.pin = ""
        } else if let scannedPin = components.queryItems?.first(where: { $0.name == "connection.pin" })?.value,
            scannedPin.range(of: #"^[A-Za-z0-9]{8,64}$"#, options: .regularExpression) != nil {
            connection.pin = scannedPin
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        connection.serverAddress = components.string ?? value
        connection.errorMessage = nil
        return true
    }

    /// 用 Keychain 里保存的登录态恢复连接（不要求密码）。
    ///
    /// 顺序：先放回保存的 cookie 直接拉会话；失败再用长期设备凭证换新票重试。
    /// 两者都没有或都失效时返回 false，由调用方退回「请输入密码」。
    @MainActor
    func restoreSavedSession(for address: String) async -> Bool {
        guard let base = try? Self.serverURL(from: address) else { return false }
        ConnectionVault.restoreAuthCookies(to: base, address: address)
        do {
            sessionStore.sessions = try await fetchSessions()
            connection.isConnected = true
            connection.errorMessage = nil
            recordDiagnostic("用已保存的登录态恢复：\(DSHURL.redactedAddress(address))")
            return true
        } catch {
            // cookie 失效（DSH 重启过）：用设备凭证换新票再试一次。
            guard ConnectionVault.loadDeviceToken(for: address) != nil,
                  await tryRefreshAuth() else { return false }
            do {
                sessionStore.sessions = try await fetchSessions()
                connection.isConnected = true
                connection.errorMessage = nil
                recordDiagnostic("设备凭证换票恢复：\(DSHURL.redactedAddress(address))")
                return true
            } catch {
                return false
            }
        }
    }

    @MainActor
    func connect() async {
        connection.errorMessage = nil
        connection.addressNeedsRescan = false
        let url: URL
        do {
            url = try Self.serverURL(from: connection.serverAddress)
            // 地址里可能带扫码的配对 token：只留 scheme/host/端口，token 不落到存档和日志里。
            connection.serverAddress = DSHURL.baseAddress(url)
        } catch {
            // 地址在发请求之前就解析不了：属于「地址无效」，不是网络问题。
            let failure = ConnectFailureMessage(error: error, context: .address)
            connection.addressNeedsRescan = failure.needsRescan
            connection.errorMessage = failure.text
            recordDiagnostic("地址校验失败 [\(failure.kind.label)]：\(DSHURL.redactedAddress(connection.serverAddress)) \(ConnectFailureMessage.diagnosticText(error))")
            return
        }
        recordDiagnostic("开始连接：\(DSHURL.redacted(url))")
        // 一次性配对：扫码即登录，不需要密码。
        var pairToken = pendingPairToken
        if pairToken == nil,
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        let scanned = components.queryItems?.first(where: { $0.name == "pair" })?.value {
            pairToken = scanned
        }
        if let pairToken {
            pendingPairToken = nil
            do {
            var request = URLRequest(url: url.appending(path: "dsh-pocket-ios/pair"))
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var form = URLComponents()
            form.queryItems = [URLQueryItem(name: "token", value: pairToken)]
            request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
            request.httpShouldHandleCookies = true
            let loginSession = URLSession(configuration: .default)
            defer { loginSession.finishTasksAndInvalidate() }
            let (_, pairResponse) = try await loginSession.data(for: request)
            let jar = HTTPCookieStorage.shared.cookies(for: url) ?? []
            let hasAuth = jar.contains { $0.name.hasPrefix("dsh-auth") }
            if !hasAuth {
                // 把「到底发生了什么」记下来：这条分支以前只说「二维码失效」，
                // 但服务端日志显示配对其实是成功的（pair login ok），
                // 真正丢的是 cookie。没有这些字段就只能瞎猜（2026-11-15）。
                let status = (pairResponse as? HTTPURLResponse)?.statusCode ?? -1
                let finalURL = (pairResponse as? HTTPURLResponse)?.url?.absoluteString ?? "-"
                let names = jar.map { $0.name }.sorted().prefix(6).joined(separator: ",")
                recordDiagnostic("配对未拿到 dsh-auth：HTTP \(status)，最终 \(DSHURL.redactedAddress(finalURL))，cookie[\(jar.count)]=\(names.isEmpty ? "空" : names)（请求地址 \(DSHURL.redactedAddress(url.absoluteString))）")
            }
            guard hasAuth else { throw ConnectionError.invalidPin }
            sessionStore.sessions = try await fetchSessions()
            connection.isConnected = true
            connection.errorMessage = nil
            connection.addressNeedsRescan = false
            PinKeychain.clear()
            // 凭证落盘统一走 persistConnectedState：地址、cookie、设备凭证一个都不能漏。
            // 之前配对分支只存了后两者，导致「扫码连上 → 重装 → 又要求扫码」。
            persistConnectedState()
            if ConnectionVault.loadDeviceToken(for: connection.serverAddress) != nil {
                recordDiagnostic("已保存长期设备凭证（下次 DSH 重启免扫码）")
            } else {
                recordDiagnostic("未收到长期设备凭证：插件可能还是旧版")
            }
            recordDiagnostic("配对登录成功：会话 \(sessionStore.sessions.count) 个")
            return
            } catch {
            // 配对分支的失败不只是「二维码过期」：超时、断网也会落到这里。
            // 以前一律说二维码失效，会把网络问题误报成需要重新配对，所以交给分型判断。
            let failure = ConnectFailureMessage(error: error, context: .pairing)
            connection.addressNeedsRescan = failure.needsRescan
            connection.errorMessage = failure.text
            recordDiagnostic("配对登录失败 [\(failure.kind.label)]：\(ConnectFailureMessage.diagnosticText(error))")
            return
            }
        }
        if let token = pendingLoginToken {
            pendingLoginToken = nil
            recordDiagnostic("使用认证 URL 登录（token 长度 \(token.count)）")
            do {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "token", value: token)]
            guard let tokenURL = components?.url else { throw ConnectionError.invalidPayload }
            let loginSession = URLSession(configuration: .default)
            defer { loginSession.finishTasksAndInvalidate() }
            _ = try await loginSession.data(from: tokenURL)
            let hasAuth = HTTPCookieStorage.shared.cookies(for: url)?.contains { $0.name.hasPrefix("dsh-auth") } ?? false
            guard hasAuth else { throw ConnectionError.invalidPin }
            sessionStore.sessions = try await fetchSessions()
            connection.isConnected = true
            connection.errorMessage = nil
            connection.addressNeedsRescan = false
            PinKeychain.save(connection.pin)
            await syncPushRegistration()
            ConnectionVault.saveAuthCookies(from: url, address: connection.serverAddress)
            recordDiagnostic("token 登录成功：会话 \(sessionStore.sessions.count) 个")
            return
            } catch {
            // 同上：登录链接失效和网络超时是两回事，分别给「重新复制地址」和「稍后重试」。
            let failure = ConnectFailureMessage(error: error, context: .loginToken)
            connection.addressNeedsRescan = failure.needsRescan
            connection.errorMessage = failure.text
            recordDiagnostic("token 登录失败 [\(failure.kind.label)]：\(ConnectFailureMessage.diagnosticText(error))")
            return
            }
        }
        // 没有密码时先别急着要密码：这台电脑如果连过，Keychain 里有 cookie
        // 或长期设备凭证，直接用它们恢复，用户点一下历史连接就能进去。
        // 之前的实现是「pin 为空 → 立刻报请输入密码」，历史连接等于没用
        // （2026-11-15 用户反馈：点完还是让他输密码）。
        if connection.pin.isEmpty {
            if await restoreSavedSession(for: connection.serverAddress) {
                return
            }
            connection.errorMessage = ConnectFailureMessage.pinMissing().text
            return
        }
        // 访问密码只允许 8-64 位字母或数字；避免把密码管理器自动填入的长密码发给服务器后变成“密码错误”。
        guard connection.pin.range(of: #"^[A-Za-z0-9]{8,64}$"#, options: .regularExpression) != nil else {
            connection.errorMessage = ConnectFailureMessage.pinFormatInvalid().text
            recordDiagnostic("密码格式无效（长度 \(connection.pin.count)），未发起请求")
            return
        }
        connection.isConnecting = true
        defer { connection.isConnecting = false }
        // 登录请求需要跟随 302 回到 `/?dsh-pocket-auth=1`，代理会借此完成 dsh web 的
        // 启动 token 握手并写入 dsh-auth cookie；因此必须跟随重定向，只是要记录是否发生过。
        let recorder = LoginRedirectRecorder()
        let loginSession = URLSession(configuration: .default, delegate: recorder, delegateQueue: nil)
        defer { loginSession.finishTasksAndInvalidate() }
        do {
            // 登录只走本插件自带的端点，**不依赖任何第三方插件**：
            //   POST /dsh-pocket-ios/login  form: token=<PIN>
            //   校验通过 → 302 到 DSH 的 browser-auth token URL，种 dsh-auth cookie。
            // 以前这里还有「插件 404 时回退 dsh-pocket 的 /pocket-login」的分支，已删除：
            // dsh-pocket-ios 是连接的必要条件，没装就该明确报错，而不是悄悄换协议。
            func postForm(_ path: String) async throws -> (HTTPURLResponse, Bool) {
            var request = URLRequest(url: url.appending(path: path))
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var body = URLComponents()
            body.queryItems = [URLQueryItem(name: "token", value: connection.pin)]
            request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
            request.httpShouldHandleCookies = true
            let (_, response) = try await loginSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ConnectionError.unexpectedResponse }
            return (http, recorder.redirected)
            }

            var loginOK = false
            let (pluginHTTP, pluginRedirected) = try await postForm("dsh-pocket-ios/login")
            let hasDSHAuth = HTTPCookieStorage.shared.cookies(for: url)?.contains { $0.name.hasPrefix("dsh-auth") } ?? false
            recordDiagnostic("插件登录：HTTP \(pluginHTTP.statusCode)，重定向=\(pluginRedirected ? "是" : "否")，dsh-auth cookie=\(hasDSHAuth ? "有" : "无")")
            if (200..<400).contains(pluginHTTP.statusCode), hasDSHAuth || pluginRedirected {
            loginOK = true
            } else if pluginHTTP.statusCode == 404 || pluginHTTP.statusCode == 405 {
            // 端点不存在 = 电脑上没装（或版本过旧）dsh-pocket-ios。这不该被报成「密码错」。
            recordDiagnostic("登录端点不存在（HTTP \(pluginHTTP.statusCode)）：dsh-pocket-ios 可能未安装或版本过旧")
            throw ConnectionError.remote("电脑上没有安装手机连接插件（dsh-pocket-ios），或版本过旧")
            } else if pluginHTTP.statusCode == 401 {
            throw ConnectionError.invalidPin
            }
            guard loginOK else { throw ConnectionError.invalidPin }

            sessionStore.sessions = try await fetchSessions()
            connection.isConnected = true
            connection.addressNeedsRescan = false
            persistConnectedState()
            connection.pin = ""
            recordDiagnostic("连接成功：会话 \(sessionStore.sessions.count) 个")
            // 连上就开探测：设置页只是「查看」，不该是探测的前置条件。
            // 否则用户不开设置页时遥测里的 probes 永远是 pending，服务端也没法分析。
            probeRunner.start(addresses: savedEndpoints.map(\.address))
        } catch {
            // 密码登录分支：invalidPin 是密码问题，URLError 是网络问题，由分型决定说什么。
            applyConnectError(error, context: .password)
        }
    }

    /// 是否是「公网隧道地址已失效 / 证书对不上」这类错误（Live、会话列表用它区分重试与重新扫码）。
    /// 具体判断收在 ConnectFailureMessage 里，和分型文案共用同一套状态码/证书码，避免两处各写一份。
    func isStaleTunnelError(_ error: Error) -> Bool {
        ConnectFailureMessage.isStaleTunnel(error)
    }

    /// 连接失败 → 分型文案。分类规则全在 ConnectFailureMessage 里，这里只负责落到界面状态。
    /// 诊断记录仍写原始错误类型：用户看到的是人话，排查时要的是错误原文，两边都不能少。
    @MainActor
    func applyConnectError(_ error: Error, context: ConnectFailureMessage.Context = .general) {
        let failure = ConnectFailureMessage(error: error, context: context)
        connection.addressNeedsRescan = failure.needsRescan
        connection.errorMessage = failure.text
        recordDiagnostic("连接失败 [\(failure.kind.label)]：\(ConnectFailureMessage.diagnosticText(error))")
    }

    /// 整理用户输入：去掉首尾空白和零宽字符，缺少协议时补 `http://`。
    static func normalizedAddress(_ rawValue: String) -> String {
        DSHURL.normalizedBase(rawValue)?.absoluteString ?? rawValue
    }

    static func serverURL(from rawValue: String) throws -> URL {
        let value = normalizedAddress(rawValue)
        guard !value.isEmpty,
            let components = URLComponents(string: value),
            let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
            let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil,
            components.query == nil, components.fragment == nil,
            components.path.isEmpty || components.path == "/",
            let url = components.url else {
            throw ConnectionError.invalidURL(rawValue)
        }
        return url
    }

    /// 构造 `ws(s)://host[:port]/path`。关键点：`URLComponents.url` 在 path 不以 "/"
    /// 开头时会返回 nil，而 `appendingPathComponent` 对空 path 恰好拼出 "api/remote.mux"。
    /// 这个 nil 曾导致实时 follow 静默不启动、归档查询抛 invalidURL，务必显式补斜杠。
    static func webSocketURL(from base: URL, path: String) -> URL? {
        DSHURL.webSocketURL(from: base, path: path)
    }

    @MainActor
    func beginQuote(_ message: PocketMessage) {
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        withAnimation(PocketMotion.animation(.easeInOut(duration: 0.18))) {
            pendingQuote = PendingQuote(
            id: message.id,
            sequence: message.sequence,
            sender: message.isUser ? L10n.t("你") : "DSH",
            text: text
            )
        }
        focusComposerTick += 1
    }

    @MainActor
    func cancelQuote() {
        withAnimation(PocketMotion.animation(.easeInOut(duration: 0.18))) { pendingQuote = nil }
    }

    /// 把待引用内容转成 Markdown 引用块（DSH 协议只认文本，不携带消息 ID）。
    func quotedPrefix(for quote: PendingQuote) -> String {
        let lines = quote.text.split(separator: "\n", omittingEmptySubsequences: false)
        let quoted = lines.map { "> \($0)" }.joined(separator: "\n")
        return quoted + "\n\n"
    }
    /// 商店截图的连接页：示例地址，不生成、不展示二维码。
    func seedStoreShotHome() {
        let en = LanguageStore.shared.isEnglish
        connection.pin = ""
        connection.errorMessage = nil
        connection.serverAddress = "https://studio.example.ts.net"
        UserDefaults.standard.set(connection.serverAddress, forKey: "dsh-pocket.store-shot-address")
        let now = Date().timeIntervalSince1970
        savedEndpoints = [
            SavedEndpoint(address: "https://studio.example.ts.net", kind: .publicNetwork,
            lastUsedAt: now, label: en ? "Home" : "家"),
            SavedEndpoint(address: "http://192.0.2.20:3091", kind: .lan,
            lastUsedAt: now - 3600, label: en ? "Office" : "公司")
        ]
    }

    /// 连接成功后统一落盘。地址、登录 cookie、设备凭证三者缺一都会导致「重装后又要求扫码」，
    /// 所以只允许从这一处写——两条成功路径（扫码配对 / 密码登录）都调它。
    @MainActor
    func persistConnectedState() {
        UserDefaults.standard.set(connection.serverAddress, forKey: Self.savedServerAddressKey)
        // Keychain 供重装后恢复（沙盒会清，Keychain 不会）。
        ConnectionVault.saveAddress(connection.serverAddress)
        if let url = try? Self.serverURL(from: connection.serverAddress) {
            ConnectionVault.saveAuthCookies(from: url, address: connection.serverAddress)
            ConnectionVault.saveDeviceToken(from: url, address: connection.serverAddress)
        }
        recordEndpoint(connection.serverAddress)
    }

    /// 自动选路：探测所有已保存地址，按策略挑一条并切换过去。
    ///
    /// 三条约束：
    /// - **只在「没有未完成请求」时切**：正在等回复时切换会把请求打断；
    /// - **只在地址真的不同才切**：避免无意义地重连；
    /// - **失败静默**：选路失败就保持现状，不影响用户当前使用。
    @MainActor
    func autoRouteIfEnabled() async {
        guard autoRouteEnabled, !isDemoMode, connection.isConnected else { return }
        // 只在「正在补发」时推迟。
        //
        // 之前用「发件箱非空」当守卫是错的：pending 里可能有历史遗留条目（服务端已确认
        // 但本地还没清），那会让自动选路永远不生效（实测：pending=2 卡住整个功能）。
        // 切换地址本身不丢消息——Outbox 按 rpcId 去重，换路后重发是安全的。
        guard !outbox.flushInFlight else {
            recordDiagnostic("自动选路推迟：正在补发")
            return
        }
        let addresses = savedEndpoints.map(\.address)
        guard addresses.count > 1 else { return }   // 只有一条路没有选择余地

        await probeRunner.probeRound(addresses: addresses)
        let candidates = savedEndpoints.compactMap { endpoint -> RouteCandidate? in
            switch probeRunner.results[endpoint.address] {
            case .reachable(let value):
                return RouteCandidate(
                    address: endpoint.address,
                    kind: DSHEndpointKind(rawValue: Self.endpointKind(of: endpoint.address).rawValue) ?? .custom,
                    reachable: true,
                    rttMs: value
                )
            case .unreachable:
                return RouteCandidate(
                    address: endpoint.address,
                    kind: DSHEndpointKind(rawValue: Self.endpointKind(of: endpoint.address).rawValue) ?? .custom,
                    reachable: false,
                    rttMs: nil
                )
            case .none:
                return nil    // 还没探测过，不参与选择
            }
        }
        guard let target = RoutePolicy.choose(from: candidates, preference: .lanFirst),
              target != connection.serverAddress else { return }

        recordDiagnostic("自动选路：切换到 \(DSHURL.redactedAddress(target))")
        connection.serverAddress = target
        connection.errorMessage = nil
        await connect()
    }

}
