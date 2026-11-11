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
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)"
        liveDiagnosticHistory.append(line)
        if liveDiagnosticHistory.count > 30 { liveDiagnosticHistory.removeFirst(liveDiagnosticHistory.count - 30) }
        NSLog("DSH_DIAG %@", line)
        Self.appendDiagnosticFile(line)
    }

    /// 设备日志不可靠（idevicesyslog 过滤/断连），同时落盘到 App 沙盒，
    /// 可通过 `devicectl device copy from --domain-type appDataContainer` 直接拉取。
    static func appendDiagnosticFile(_ line: String) {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = directory.appendingPathComponent("diagnostics.log")
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    @MainActor
    func diagnosticReport() -> String {
        captureDiagnosticSample()
        let title = currentConversationTitle.isEmpty ? "未打开会话" : currentConversationTitle
        let visits = diagnosticVisits.map(\.line)
        let rows = diagnosticSamples.map(\.line)
        return """
        \(title)
        进出
        \(visits.isEmpty ? "还没有进出记录" : visits.joined(separator: "\n"))
        此刻
        \(diagnosticMemoryLine())
        采样
        \(rows.isEmpty ? "还没有采样" : rows.joined(separator: "\n"))
        """
    }

    /// 最近一小段时间的采样。进出记录不随再次进入清掉。
    @MainActor
    func startDiagnosticSampler() {
        guard diagnosticSampleTask == nil else { return }
        diagnosticSampleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if Task.isCancelled { break }
                await MainActor.run { self?.captureDiagnosticSample() }
            }
        }
    }

    @MainActor
    func beginDiagnosticVisit(reusedMessages: Int) {
        let visit = DiagnosticVisit(
            index: (diagnosticVisits.last?.index ?? 0) + 1,
            enterMs: nil,
            leaveMs: nil,
            reusedMessages: reusedMessages,
            memoryEnter: Int(Self.memoryFootprintMB().rounded()),
            memoryLeave: nil,
            viewsAfterLeave: nil
        )
        diagnosticVisits.append(visit)
        if diagnosticVisits.count > 6 {
            diagnosticVisits.removeFirst(diagnosticVisits.count - 6)
        }
        captureDiagnosticSample()
    }

    @MainActor
    func finishDiagnosticVisit(leaveMs: Int) {
        guard let index = diagnosticVisits.lastIndex(where: { $0.leaveMs == nil }) else { return }
        diagnosticVisits[index].leaveMs = leaveMs
        diagnosticVisits[index].memoryLeave = Int(Self.memoryFootprintMB().rounded())
        let visitIndex = diagnosticVisits[index].index
        captureDiagnosticSample()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard let slot = self.diagnosticVisits.lastIndex(where: { $0.index == visitIndex }),
                  self.diagnosticVisits[slot].leaveMs != nil,
                  self.visibleSessionId == nil else { return }
            self.diagnosticVisits[slot].viewsAfterLeave = ConversationViewLifetime.liveCount
        }
    }

    func diagnosticMemoryLine() -> String {
        let detail = Self.memoryBreakdown()
        let kept = retainedConversationStats()
        let images = ImageMemory.shared.stats()
        return "内存 \(detail.footprintMB)MB  压缩 \(detail.compressedMB)MB  图 \(images.count)张/\(Self.formatBytes(images.bytes))  文字 \(Self.formatBytes(kept.textBytes))  过程正文 \(Self.formatBytes(kept.stepBytes))  页 \(ConversationViewLifetime.liveCount)  留着会话 \(kept.sessions)（消息 \(kept.messages)）"
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
        diagnosticSampleTask?.cancel()
        diagnosticSampleTask = nil
    }

    @MainActor
    func captureDiagnosticSample(enterMs: Int? = nil) {
        let counts = diagnosticSendCounts()
        let sample = DiagnosticSample(
            at: Date(),
            memoryMB: Int(Self.memoryFootprintMB().rounded()),
            pending: counts.pending,
            queued: counts.queued,
            failed: counts.failed,
            network: diagnosticNetworkLabel(),
            enterMs: enterMs
        )
        if let last = diagnosticSamples.last,
           enterMs == nil,
           last.at.timeIntervalSinceNow > -2,
           last.pending == sample.pending,
           last.queued == sample.queued,
           last.failed == sample.failed,
           last.network == sample.network,
           last.memoryMB == sample.memoryMB {
            return
        }
        diagnosticSamples.append(sample)
        if diagnosticSamples.count > 18 {
            diagnosticSamples.removeFirst(diagnosticSamples.count - 18)
        }
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
    func conversationDiagnosticsBlock() -> String {
        let s = conversationSizeSnapshot()
        let load = s.loadMs.map { "\($0) ms，来源 \(s.loadSource ?? "未知")" } ?? "这次打开还没记到加载完成"
        let log = sessionLogPath ?? "没有 cwd，推不出电脑上的会话日志路径"
        return """
        --- 状态索引 ---
        这份文本是给排查用的，不是给用户看的菜单。上面是此刻的汇总，下面是最近事件。要更早的记录，按「去哪看」取文件。

        会话: \(s.title)
        地址: \(sessionAddress.isEmpty ? "未打开会话" : sessionAddress)
        电脑日志: \(log)
        手机日志: App 沙盒 Documents/diagnostics.log。用 devicectl device copy from --domain-type appDataContainer 拉取。控制台过滤 DSH_DIAG。
        会话日志格式: ~/.dsh/sessions/--<cwd 里的 / 换成 ->--/<sessionId>/session.v4.jsonl.zstd

        消息 \(s.messages)（用户 \(s.userMessages) / 助手 \(s.assistantMessages) / 待发 \(s.pendingMessages)）
        含义: 手机上这次加载进来的消息条数，不是电脑上的全部历史。待发是还没被服务端确认的本地气泡。
        还有更早: \(s.hasMore ? "是，向上翻还会再拉" : "否，当前窗口已经到最早")

        过程 \(s.steps)（未完成 \(s.unfinishedSteps) / 出错 \(s.errorSteps) / 界面上折叠成 \(s.stepGroups) 组）
        含义: 工具步骤。未完成=还在跑；出错=工具结果是错误。组数才是屏幕上画出来的过程行，不要用步骤数当行数。
        失败轮次: \(s.failures)。时间线上要布局的行: \(s.timelineRows)（消息 + 过程组 + 失败提示）。

        文本体积: 消息 \(Self.formatBytes(s.messageBytes))，过程结果 \(Self.formatBytes(s.stepBytes))
        含义: 只算已留在内存里的文字。过程正文默认不保留，展开后才会变大。这不是 内存 那一项。

        图片 \(s.images) 张，缩略图缓存 \(s.cachedImages) 张 / \(Self.formatBytes(s.cachedImageBytes))
        含义: 图片引用数，加上 ImageMemory 里实际解码的缩略图。缓存有上限（48 张 / 32 MB）。全尺寸图不应该留在这里。

        会话页还活着: \(s.liveViews)
        含义: ConversationView 实例数。离开会话后应回到 0。大于 1 说明旧页面没释放，反复进出时内存会叠。

        上次加载: \(load)
        含义: 从开始打开到首屏内容到齐的耗时。follow=实时流快照，history=HTTP 拉的历史。慢的时候先看过程组数和图片数，不要先怪网络。

        App 内存: \(s.memoryMB) MB
        含义: phys_footprint，整个进程现在有多重，不是这段对话的文本大小。iOS 杀后台看的就是这个数。文字通常只有几十 KB；涨到几百 MB 时先看图片缓存和会话页是否还活着。

        --- 最近事件（最多 30 条，更早的在手机日志文件） ---
        """
    }

    func conversationSizeSnapshot() -> ConversationSizeSnapshot {
        let user = messages.filter(\.isUser).count
        let pending = messages.filter(\.isPending).count
        let groups = stepGroups.count
        let failures = turnFailures.count
        return ConversationSizeSnapshot(
            title: currentConversationTitle,
            messages: messages.count,
            userMessages: user,
            assistantMessages: messages.count - user,
            pendingMessages: pending,
            steps: steps.count,
            unfinishedSteps: steps.filter { !$0.finished }.count,
            errorSteps: steps.filter(\.isError).count,
            stepGroups: groups,
            failures: failures,
            timelineRows: messages.count + groups + failures,
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
            memoryMB: String(format: "%.1f", Self.memoryFootprintMB())
        )
    }

    /// Jetsam 看的物理占用，比 resident size 更接近「这个 App 现在有多重」。
    static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1_048_576
    }

    static func memoryBreakdown() -> (footprintMB: Int, compressedMB: Int) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (-1, -1) }
        let footprint = Int((Double(info.phys_footprint) / 1_048_576).rounded())
        let compressed = Int((Double(info.compressed) / 1_048_576).rounded())
        return (footprint, compressed)
    }

    static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    @MainActor
    func noteLoadFinished(source: String, conversation: ConversationState) {
        guard conversation.loadTimingPending, let started = conversation.loadStartedAt else { return }
        conversation.loadTimingPending = false
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        conversation.lastLoadMs = ms
        conversation.lastLoadSource = source
        recordDiagnostic("会话加载 \(ms) ms source=\(source) 消息=\(conversation.messages.count) 过程=\(conversation.steps.count)")
        captureDiagnosticSample(enterMs: ms)
        if let index = diagnosticVisits.lastIndex(where: { $0.leaveMs == nil }) {
            diagnosticVisits[index].enterMs = ms
        }
    }

    @discardableResult
    func useScannedAddress(_ value: String) -> Bool {
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              components.host != nil else {
            errorMessage = "二维码中没有有效的 HTTP 或 HTTPS 地址。"
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
        let url: URL
        do {
            url = try Self.serverURL(from: serverAddress)
            // 地址里可能带扫码的配对 token：只留 scheme/host/端口，token 不落到存档和日志里。
            serverAddress = DSHURL.baseAddress(url)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "地址格式无效。"
            recordDiagnostic("地址校验失败：\(DSHURL.redactedAddress(serverAddress))")
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
                PinKeychain.clear()
                recordDiagnostic("配对登录成功：会话 \(sessions.count) 个")
                return
            } catch {
                errorMessage = "配对二维码已失效（60 秒有效、仅可使用一次），请在电脑上重新生成后扫码。"
                recordDiagnostic("配对登录失败：\(error.localizedDescription)")
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
                PinKeychain.save(pin)
                await syncPushRegistration()
                recordDiagnostic("token 登录成功：会话 \(sessions.count) 个")
                return
            } catch {
                errorMessage = "登录链接已失效（DSH 重启后 token 会变化），请重新在设置页复制最新地址或输入访问密码。"
                recordDiagnostic("token 登录失败：\(error.localizedDescription)")
                return
            }
        }
        // 访问密码只允许 8-64 位字母或数字；避免把密码管理器自动填入的长密码发给服务器后变成“密码错误”。
        guard pin.range(of: #"^[A-Za-z0-9]{8,64}$"#, options: .regularExpression) != nil else {
            errorMessage = "访问密码需为 8–64 位英文字母或数字，请重新输入（不要使用密码管理器的自动填充）。"
            recordDiagnostic("密码格式无效（长度 \(pin.count)），未发起请求")
            return
        }
        guard !pin.isEmpty else {
            errorMessage = "请输入访问密码"
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
            UserDefaults.standard.set(serverAddress, forKey: Self.savedServerAddressKey)
            recordEndpoint(serverAddress)
            pin = ""
            recordDiagnostic("连接成功：会话 \(sessions.count) 个")
        } catch {
            recordDiagnostic("连接失败：\(error.localizedDescription)")
            applyConnectError(error)
        }
    }

    /// 连接错误 → 用户能看懂的提示；TLS/主机不可达时提示地址已失效并引导重新扫码。
    /// 是否是"公网隧道地址已失效/隧道未连接"这类错误（Cloudflare 常见 5xx）。
    func isStaleTunnelError(_ error: Error) -> Bool {
        if case .server(let code) = error as? ConnectionError {
            return [502, 503, 504, 520, 521, 522, 523, 524, 530].contains(code)
        }
        if let urlError = error as? URLError {
            return [.secureConnectionFailed, .serverCertificateUntrusted,
                    .serverCertificateHasBadDate, .serverCertificateNotYetValid,
                    .serverCertificateHasUnknownRoot].contains(urlError.code)
        }
        return false
    }

    func applyConnectError(_ error: Error) {
        if isStaleTunnelError(error) {
            addressNeedsRescan = true
            errorMessage = "公网隧道暂时连不上（HTTP 530）：电脑上的隧道可能已重启、公网地址已经变化。请在电脑上重新打开「手机访问」并用二维码重新扫码；同一 Wi-Fi 下也可以改用局域网地址。"
            return
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .secureConnectionFailed, .serverCertificateUntrusted,
                 .serverCertificateHasBadDate, .serverCertificateNotYetValid,
                 .serverCertificateHasUnknownRoot, .clientCertificateRejected:
                addressNeedsRescan = true
                errorMessage = "无法建立安全连接：电脑的公网地址可能已失效。隧道重启后会分配新地址，请在电脑上打开 DSH → 设置 → 手机访问，用这里的二维码重新扫描；同一 Wi-Fi 下也可以改用局域网地址。"
                return
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost, .notConnectedToInternet:
                addressNeedsRescan = true
                errorMessage = "连不上电脑：请确认电脑和手机网络正常、DSH 的「手机访问」仍开着；如果公网地址变了，请重新扫码。"
                return
            case .timedOut:
                errorMessage = "连接超时：电脑端可能正忙或网络不稳定，请稍后重试。"
                return
            default:
                break
            }
        }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
        withAnimation(.easeInOut(duration: 0.18)) {
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
        withAnimation(.easeInOut(duration: 0.18)) { pendingQuote = nil }
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
