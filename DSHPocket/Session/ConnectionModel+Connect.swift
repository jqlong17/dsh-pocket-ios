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

    @MainActor
    func recordDiagnostic(_ message: String) {
        diagnostics.record(message)
    }

    /// 诊断文本的拼装在 Diagnostics（spec/12）；这里只聚合标题与内存行。
    @MainActor
    func diagnosticReport() -> String {
        captureDiagnosticSample()
        let title = currentConversationTitle.isEmpty ? "未打开会话" : currentConversationTitle
        return diagnostics.report(title: title, memoryLine: diagnosticMemoryLine())
    }

    /// 最近一小段时间的采样。进出记录不随再次进入清掉。
    @MainActor
    func startDiagnosticSampler() {
        diagnostics.startSampler { [weak self] in
            self?.captureDiagnosticSample()
        }
    }

    func diagnosticMemoryLine() -> String { diagnostics.memoryLine() }

    /// 会话规模快照：读模型状态，因此留在模型侧；文本拼装在 Diagnostics。
    func conversationSizeSnapshot() -> ConversationSizeSnapshot {
        let user = messages.filter(\.isUser).count
        return ConversationSizeSnapshot(
            title: currentConversationTitle,
            messages: messages.count,
            userMessages: user,
            assistantMessages: messages.count - user,
            pendingMessages: messages.filter(\.isPending).count,
            steps: steps.count,
            unfinishedSteps: steps.filter { !$0.finished }.count,
            errorSteps: steps.filter(\.isError).count,
            stepGroups: stepGroups.count,
            failures: turnFailures.count,
            timelineRows: messages.count + stepGroups.count + turnFailures.count,
            messageBytes: messages.reduce(0) { $0 + $1.text.utf8.count },
            stepBytes: steps.reduce(0) { $0 + $1.resultText.utf8.count + $1.detail.utf8.count },
            images: messages.reduce(0) { $0 + $1.images.count + $1.localImages.count }
                + steps.reduce(0) { $0 + $1.images.count },
            cachedImages: ImageMemory.shared.stats().count,
            cachedImageBytes: ImageMemory.shared.stats().bytes,
            liveViews: ConversationViewLifetime.liveCount,
            hasMore: hasMoreOlder,
            loadMs: activeConversation?.lastLoadMs,
            loadSource: activeConversation?.lastLoadSource,
            memoryMB: String(format: "%.1f", Diagnostics.memoryFootprintMB())
        )
    }

    /// 装配诊断的数据来源（幂等）。诊断不反向依赖模型，所以用闭包注入。
    func installDiagnosticsProviders() {
        guard diagnostics.providers == nil else { return }
        diagnostics.providers = Diagnostics.Providers(
            memoryBreakdown: { Diagnostics.memoryBreakdown() },
            retainedStats: { [weak self] in
                self?.retainedConversationStats() ?? (0, 0, 0, 0)
            },
            sendCounts: { [weak self] in
                self?.diagnosticSendCounts() ?? (0, 0, 0)
            },
            networkLabel: { [weak self] in
                self?.diagnosticNetworkLabel() ?? "未知"
            },
            conversationStats: { [weak self] in
                self?.conversationSizeSnapshot() ?? ConversationSizeSnapshot(
                    title: "", messages: 0, userMessages: 0, assistantMessages: 0,
                    pendingMessages: 0, steps: 0, unfinishedSteps: 0, errorSteps: 0,
                    stepGroups: 0, failures: 0, timelineRows: 0, messageBytes: 0,
                    stepBytes: 0, images: 0, cachedImages: 0, cachedImageBytes: 0,
                    liveViews: 0, hasMore: false, loadMs: nil, loadSource: nil, memoryMB: "—")
            },
            logPath: { [weak self] in self?.sessionLogPath },
            sessionAddress: { [weak self] in self?.sessionAddress ?? "" }
        )
    }

    func conversationDiagnosticsBlock() -> String { diagnostics.indexBlock() }

    @MainActor
    func beginDiagnosticVisit(reusedMessages: Int) {
        diagnostics.beginVisit(reusedMessages: reusedMessages,
                               memoryMB: Int(Diagnostics.memoryFootprintMB().rounded()))
        captureDiagnosticSample()
    }

    @MainActor
    func finishDiagnosticVisit(leaveMs: Int) {
        guard let visitIndex = diagnostics.finishVisit(leaveMs: leaveMs,
                                                       memoryMB: Int(Diagnostics.memoryFootprintMB().rounded())) else { return }
        captureDiagnosticSample()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard self.visibleSessionId == nil else { return }
            self.diagnostics.setViewsAfterLeave(visitIndex: visitIndex,
                                                views: ConversationViewLifetime.liveCount)
        }
    }

     func retainedConversationStats() -> (sessions: Int, messages: Int, textBytes: Int, stepBytes: Int) {
        var messageCount = 0
        var textBytes = 0
        var stepBytes = 0
        for conversation in conversations.values {
            messageCount += conversation.messages.count
            textBytes += conversation.messages.reduce(0) { $0 + $1.text.utf8.count }
            stepBytes += conversation.steps.reduce(0) { $0 + $1.resultText.utf8.count + $1.detail.utf8.count }
        }
        return (conversations.count, messageCount, textBytes, stepBytes)
    }

    @MainActor
    func stopDiagnosticSampler() {
        diagnostics.stopSampler()
    }

    /// 采样一行。计算与去重在 Diagnostics（用 providers 读模型状态），这里只转发。
    @MainActor
    func captureDiagnosticSample(enterMs: Int? = nil) {
        diagnostics.capture(enterMs: enterMs)
    }

    func noteNetworkEdgeForDiagnostics() {
        switch liveConnection {
        case .disconnected, .reconnecting:
            if networkDownSince == nil { networkDownSince = Date() }
        default:
            networkDownSince = nil
        }
    }

    func diagnosticNetworkLabel() -> String {
        switch liveConnection {
        case .connected:
            return "通"
        case .demo:
            return "演示"
        case .connecting:
            return "连接中"
        case .reconnecting:
            let seconds = Int(Date().timeIntervalSince(networkDownSince ?? Date()))
            return "重连 \(max(seconds, 0)) 秒"
        case .disconnected:
            let seconds = Int(Date().timeIntervalSince(networkDownSince ?? Date()))
            return "断 \(max(seconds, 0)) 秒"
        case .idle:
            return "未连接"
        }
    }

    func diagnosticSendCounts() -> (pending: Int, queued: Int, failed: Int) {
        var pending = 0
        var queued = 0
        var failed = 0
        for message in messages where message.isPending {
            switch pendingSendState(for: message) {
            case .failed:
                failed += 1
            case .queued:
                queued += 1
            case .sending, .none:
                pending += 1
            case .acked:
                break
            }
        }
        return (pending, queued, failed)
    }

    /// 复制出来给排查用的状态索引。菜单里不展示这些数字。
      /// Jetsam 看的物理占用，比 resident size 更接近「这个 App 现在有多重」。
       @MainActor
    func noteLoadFinished(source: String, conversation: ConversationState) {
        guard conversation.loadTimingPending, let started = conversation.loadStartedAt else { return }
        conversation.loadTimingPending = false
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        conversation.lastLoadMs = ms
        conversation.lastLoadSource = source
        recordDiagnostic("会话加载 \(ms) ms source=\(source) 消息=\(conversation.messages.count) 过程=\(conversation.steps.count)")
        captureDiagnosticSample(enterMs: ms)
        diagnostics.setEnterMsForOpenVisit(ms)
    }

    @discardableResult
    func useScannedAddress(_ value: String) -> Bool {
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              components.host != nil else {
            // 扫到的不是电脑地址：属于「地址无效」，提示里直接引导再扫一次，所以给重新扫码入口。
            let failure = ConnectFailureMessage.scannedAddressInvalid()
            addressNeedsRescan = failure.needsRescan
            errorMessage = failure.text
            return false
        }
        // 二维码/粘贴的地址可能携带：?token=<DSH 认证 token>（登录后浏览器地址栏），或旧版 ?pin=<密码>。
        if let pairToken = components.queryItems?.first(where: { $0.name == "pair" })?.value,
           !pairToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingPairToken = pairToken
            pin = ""
        } else if let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
           !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingLoginToken = token
            pin = ""
        } else if let scannedPin = components.queryItems?.first(where: { $0.name == "pin" })?.value,
                  scannedPin.range(of: #"^[A-Za-z0-9]{8,64}$"#, options: .regularExpression) != nil {
            pin = scannedPin
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        serverAddress = components.string ?? value
        errorMessage = nil
        return true
    }

    @MainActor
    func connect() async {
        errorMessage = nil
        addressNeedsRescan = false
        let url: URL
        do {
            url = try Self.serverURL(from: serverAddress)
            // 地址里可能带扫码的配对 token：只留 scheme/host/端口，token 不落到存档和日志里。
            serverAddress = DSHURL.baseAddress(url)
        } catch {
            // 地址在发请求之前就解析不了：属于「地址无效」，不是网络问题。
            let failure = ConnectFailureMessage(error: error, context: .address)
            addressNeedsRescan = failure.needsRescan
            errorMessage = failure.text
            recordDiagnostic("地址校验失败 [\(failure.kind.label)]：\(DSHURL.redactedAddress(serverAddress)) \(ConnectFailureMessage.diagnosticText(error))")
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
                _ = try await loginSession.data(for: request)
                let hasAuth = HTTPCookieStorage.shared.cookies(for: url)?.contains { $0.name.hasPrefix("dsh-auth") } ?? false
                guard hasAuth else { throw ConnectionError.invalidPin }
                sessions = try await fetchSessions()
                isConnected = true
                errorMessage = nil
                addressNeedsRescan = false
                PinKeychain.clear()
                recordDiagnostic("配对登录成功：会话 \(sessions.count) 个")
                return
            } catch {
                // 配对分支的失败不只是「二维码过期」：超时、断网也会落到这里。
                // 以前一律说二维码失效，会把网络问题误报成需要重新配对，所以交给分型判断。
                let failure = ConnectFailureMessage(error: error, context: .pairing)
                addressNeedsRescan = failure.needsRescan
                errorMessage = failure.text
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
                sessions = try await fetchSessions()
                isConnected = true
                errorMessage = nil
                addressNeedsRescan = false
                PinKeychain.save(pin)
                await syncPushRegistration()
                recordDiagnostic("token 登录成功：会话 \(sessions.count) 个")
                return
            } catch {
                // 同上：登录链接失效和网络超时是两回事，分别给「重新复制地址」和「稍后重试」。
                let failure = ConnectFailureMessage(error: error, context: .loginToken)
                addressNeedsRescan = failure.needsRescan
                errorMessage = failure.text
                recordDiagnostic("token 登录失败 [\(failure.kind.label)]：\(ConnectFailureMessage.diagnosticText(error))")
                return
            }
        }
        // 先拦空密码，再说格式：空输入报「格式不对」会让人以为密码本身有问题。
        guard !pin.isEmpty else {
            errorMessage = ConnectFailureMessage.pinMissing().text
            return
        }
        // 访问密码只允许 8-64 位字母或数字；避免把密码管理器自动填入的长密码发给服务器后变成“密码错误”。
        guard pin.range(of: #"^[A-Za-z0-9]{8,64}$"#, options: .regularExpression) != nil else {
            errorMessage = ConnectFailureMessage.pinFormatInvalid().text
            recordDiagnostic("密码格式无效（长度 \(pin.count)），未发起请求")
            return
        }
        isConnecting = true
        defer { isConnecting = false }
        // 登录请求需要跟随 302 回到 `/?dsh-pocket-auth=1`，代理会借此完成 dsh web 的
        // 启动 token 握手并写入 dsh-auth cookie；因此必须跟随重定向，只是要记录是否发生过。
        let recorder = LoginRedirectRecorder()
        let loginSession = URLSession(configuration: .default, delegate: recorder, delegateQueue: nil)
        defer { loginSession.finishTasksAndInvalidate() }
        do {
            // 登录优先走本插件自带的端点（不依赖 dsh-pocket）：
            //   POST /dsh-pocket-ios/login  form: token=<PIN>
            //   校验通过 → 302 到 DSH 的 browser-auth token URL，种 dsh-auth cookie。
            // 若插件不存在（404/405），回退到 dsh-pocket 的 /pocket-login。
            func postForm(_ path: String) async throws -> (HTTPURLResponse, Bool) {
                var request = URLRequest(url: url.appending(path: path))
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                var body = URLComponents()
                body.queryItems = [URLQueryItem(name: "token", value: pin)]
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
            } else if pluginHTTP.statusCode == 404 || pluginHTTP.statusCode == 405 || pluginHTTP.statusCode == 503 || (500..<600).contains(pluginHTTP.statusCode) {
                // 没有安装本插件：回退 dsh-pocket 的登录协议。
                let (pocketHTTP, pocketRedirected) = try await postForm("pocket-login")
                recordDiagnostic("dsh-pocket 登录回退：HTTP \(pocketHTTP.statusCode)")
                if pocketHTTP.statusCode == 429 {
                    let retryAfter = Int(pocketHTTP.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
                    throw ConnectionError.rateLimited(retryAfter)
                }
                if pocketHTTP.statusCode == 401 || pocketHTTP.statusCode == 403 { throw ConnectionError.invalidPin }
                let hasPocketCookie = HTTPCookieStorage.shared.cookies(for: url)?.contains { $0.name == "dsh_pocket_token" } ?? false
                loginOK = (200..<400).contains(pocketHTTP.statusCode) && (pocketRedirected || hasPocketCookie)
            } else if pluginHTTP.statusCode == 401 {
                throw ConnectionError.invalidPin
            }
            guard loginOK else { throw ConnectionError.invalidPin }

            sessions = try await fetchSessions()
            isConnected = true
            addressNeedsRescan = false
            UserDefaults.standard.set(serverAddress, forKey: Self.savedServerAddressKey)
            recordEndpoint(serverAddress)
            pin = ""
            recordDiagnostic("连接成功：会话 \(sessions.count) 个")
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
        addressNeedsRescan = failure.needsRescan
        errorMessage = failure.text
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
        pin = ""
        errorMessage = nil
        serverAddress = "https://studio.example.ts.net"
        UserDefaults.standard.set(serverAddress, forKey: "dsh-pocket.store-shot-address")
        let now = Date().timeIntervalSince1970
        savedEndpoints = [
            SavedEndpoint(address: "https://studio.example.ts.net", kind: .publicNetwork,
                          lastUsedAt: now, label: en ? "Home" : "家"),
            SavedEndpoint(address: "http://192.0.2.20:3091", kind: .lan,
                          lastUsedAt: now - 3600, label: en ? "Office" : "公司")
        ]
    }
}
