import SwiftUI
import VisionKit
import AVFoundation
import Observation
import PhotosUI
import UIKit
import os

private let pocketLogger = Logger(subsystem: "com.ruska.dsh-pocket-ios", category: "conversation")

private func timingLog(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) DSH_TIMING \(message)"
    NSLog("%@", line)
}

@main
struct DSHPocketApp: App {
    @State private var model = ConnectionModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.light)
        }
    }
}

@Observable
final class ConnectionModel {
    private static let savedServerAddressKey = "dsh-pocket.server-address"
    /// 只同步最近的消息：公网隧道对 WebSocket 单帧大小有限制，长会话全量同步会被拒。
    private static let conversationMessageLimit = 30
    var serverAddress = UserDefaults.standard.string(forKey: savedServerAddressKey) ?? "http://"
    var pin = ""
    var isConnecting = false
    var errorMessage: String?
    var isConnected = false
    var isDemoMode = false
    var sessions: [PocketSession] = []
    var archivedSessionIds: Set<String> = []
    var isLoadingSessions = false
    var selectedSession: PocketSession?
    var messages: [PocketMessage] = []
    var draft = ""
    var draftImages: [PocketDraftImage] = []
    var steps: [PocketStep] = []
    var navigationPath: [PocketSession] = []
    var isTurnRunning = false
    var turnStartedAt: Date?
    private static var imageCache: [String: UIImage] = [:]
    var isSending = false
    var isLoadingConversation = false
    var conversationError: String?
    var liveConnectionState = "未连接"
    var liveDiagnosticHistory: [String] = []
    var liveTask: Task<Void, Never>?
    var fallbackTask: Task<Void, Never>?
    var sendTask: Task<Void, Never>?
    private var pendingSendID: String?
    private var cancelledDraft = ""
    private var cancelledImages: [PocketDraftImage] = []

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
    private static func appendDiagnosticFile(_ line: String) {
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

    func diagnosticReport() -> String { liveDiagnosticHistory.joined(separator: "\n") }

    @discardableResult
    func useScannedAddress(_ value: String) -> Bool {
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              components.host != nil else {
            errorMessage = "二维码中没有有效的 HTTP 或 HTTPS 地址。"
            return false
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
            serverAddress = url.absoluteString
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "地址格式无效。"
            recordDiagnostic("地址校验失败：\(serverAddress.debugDescription)")
            return
        }
        recordDiagnostic("开始连接：\(url.absoluteString)")
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
            var request = URLRequest(url: url.appending(path: "pocket-login"))
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var body = URLComponents()
            body.queryItems = [URLQueryItem(name: "token", value: pin)]
            request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
            request.httpShouldHandleCookies = true
            let (_, response) = try await loginSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ConnectionError.unexpectedResponse }
            let hasPocketCookie = HTTPCookieStorage.shared.cookies(for: url)?.contains { $0.name == "dsh_pocket_token" } ?? false
            recordDiagnostic("登录响应：HTTP \(http.statusCode)，重定向=\(recorder.redirected ? "是" : "否")，pocket cookie=\(hasPocketCookie ? "有" : "无")")
            if http.statusCode == 429 {
                let retryAfter = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
                throw ConnectionError.rateLimited(retryAfter)
            }
            if http.statusCode == 401 || http.statusCode == 403 { throw ConnectionError.invalidPin }
            guard (200..<400).contains(http.statusCode) else { throw ConnectionError.server(http.statusCode) }
            // DSH Pocket 协议：密码正确 → 302 到 `/?dsh-pocket-auth=1` 并种 dsh_pocket_token
            // cookie；密码错误 → 200 + 登录页。以前把 200 当成功，导致错误密码也"连上"
            // 然后在 session/list 上撞 401，提示完全误导。
            guard recorder.redirected || hasPocketCookie else { throw ConnectionError.invalidPin }
            sessions = try await fetchSessions()
            isConnected = true
            UserDefaults.standard.set(serverAddress, forKey: Self.savedServerAddressKey)
            pin = ""
            recordDiagnostic("连接成功：会话 \(sessions.count) 个")
        } catch {
            recordDiagnostic("连接失败：\(error.localizedDescription)")
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 整理用户输入：去掉首尾空白和零宽字符，缺少协议时补 `http://`。
    private static func normalizedAddress(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        value.removeAll { character in
            character == "\u{200B}" || character == "\u{200C}" || character == "\u{200D}" || character == "\u{FEFF}"
        }
        if !value.contains("://") { value = "http://" + value }
        return value
    }

    private static func serverURL(from rawValue: String) throws -> URL {
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
    private static func webSocketURL(from base: URL, path: String) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        let secure = components.scheme == "https"
        components.scheme = secure ? "wss" : "ws"
        var target = components.path
        if !target.hasPrefix("/") { target = "/" + target }
        if target.hasSuffix("/") { target.removeLast() }
        components.path = target + "/" + path
        return components.url
    }

    @MainActor
    func restoreConnection() async {
        if isDemoMode { return }
#if DEBUG
        if DebugLaunch.showConnect { return }
        if DebugLaunch.demoMode { startDemoMode(); return }
        if let server = DebugLaunch.server {
            serverAddress = server
            if let pin = DebugLaunch.pin { self.pin = pin }
            recordDiagnostic("Debug 自动连接：\(server)")
            await connect()
            return
        }
#endif
        guard UserDefaults.standard.string(forKey: Self.savedServerAddressKey) != nil,
              (try? Self.serverURL(from: serverAddress)) != nil else { return }
        do {
            sessions = try await fetchSessions()
            isConnected = true
            errorMessage = nil
        } catch {
            isConnected = false
            errorMessage = "无法恢复上次连接（\(error.localizedDescription)），请重新输入访问密码。"
        }
    }

    @MainActor
    func disconnect() {
        if isDemoMode { exitDemoMode(); return }
        liveTask?.cancel()
        fallbackTask?.cancel()
        liveTask = nil
        selectedSession = nil
        messages = []
        sessions = []
        archivedSessionIds = []
        liveConnectionState = "未连接"
        isConnected = false
    }

    // MARK: - 演示模式（App Store 审核 / 没有电脑时体验）

    private static let demoSessionList: [PocketSession] = [
        PocketSession(sessionId: "demo-1", updatedAt: Date().timeIntervalSince1970, running: true, blank: false,
                      title: "给项目加一个登录页", cwd: "~/projects/demo-app"),
        PocketSession(sessionId: "demo-2", updatedAt: Date().timeIntervalSince1970 - 3600, running: false, blank: false,
                      title: "图片识别示例", cwd: "~/projects/demo-app"),
        PocketSession(sessionId: "demo-3", updatedAt: Date().timeIntervalSince1970 - 7200, running: false, blank: false,
                      title: "重构 Agent 上下文", cwd: "~/projects/demo-app")
    ]

    private static let demoPicture: UIImage = {
        let size = CGSize(width: 640, height: 420)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor(red: 0.12, green: 0.30, blue: 0.82, alpha: 1).cgColor,
                          UIColor(red: 0.06, green: 0.14, blue: 0.42, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero,
                                                     end: CGPoint(x: size.width, y: size.height), options: [])
            }
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 205, y: 105, width: 230, height: 210)).fill()
        }
    }()

    @MainActor
    func startDemoMode() {
        isDemoMode = true
        isConnected = true
        isConnecting = false
        errorMessage = nil
        sessions = Self.demoSessionList
        archivedSessionIds = []
        selectedSession = nil
        navigationPath = []
        messages = []
        steps = []
        liveConnectionState = "演示模式"
#if DEBUG
        if let id = DebugLaunch.sessionId, let session = Self.demoSessionList.first(where: { $0.sessionId == id }) {
            navigationPath = [session]
        }
#endif
    }

    @MainActor
    func exitDemoMode() {
        isDemoMode = false
        isConnected = false
        selectedSession = nil
        navigationPath = []
        messages = []
        steps = []
        sessions = []
        draftImages = []
        liveConnectionState = "未连接"
    }

    @MainActor
    private func openDemo(_ session: PocketSession) {
        liveTask?.cancel()
        selectedSession = session
        messages = Self.demoMessages(for: session.sessionId)
        steps = Self.demoSteps(for: session.sessionId)
        isTurnRunning = session.running
        turnStartedAt = session.running ? Date().addingTimeInterval(-37) : nil
        isLoadingConversation = false
        conversationError = nil
        draft = ""
        draftImages = []
        liveConnectionState = "演示模式"
    }

    @MainActor
    private func sendDemoMessage() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = draftImages
        guard (!text.isEmpty || !images.isEmpty), selectedSession != nil, !isSending else { return }
        let pending = PocketMessage(pendingText: text, localImages: images.map(\.uiImage))
        messages.append(pending)
        pendingSendID = pending.id
        cancelledDraft = text
        cancelledImages = images
        draft = ""
        draftImages = []
        isSending = true
        defer {
            isSending = false
            pendingSendID = nil
            cancelledDraft = ""
            cancelledImages = []
        }
        recordDiagnostic("演示模式：本地模拟发送")
        try? await Task.sleep(for: .seconds(1))
        if Task.isCancelled { return }
        messages.removeAll { $0.isPending }
        let nextSequence = (messages.map(\.sequence).max() ?? 0) + 1
        messages.append(PocketMessage(
            demoText: "（演示模式）这是内置的示例回复，不会真正调用模型。\n\n连接电脑后，消息会发给本机的 DSH，助手回复与工具过程会实时出现在这里。",
            isUser: false, sequence: nextSequence))
        messages.sort { $0.sequence < $1.sequence }
    }

    private static func demoMessages(for sessionId: String) -> [PocketMessage] {
        switch sessionId {
        case "demo-1":
            return [
                PocketMessage(demoText: "帮我看看这个项目结构，然后给登录页加个入口。", isUser: true, sequence: 1),
                PocketMessage(demoText: """
                我看了一下项目结构，主要目录如下：

                - `src/` — 业务代码
                - `src/pages/` — 页面组件
                - `public/` — 静态资源

                登录页入口可以加在 `src/router.ts`，需要我直接改吗？
                """, isUser: false, sequence: 4),
                PocketMessage(demoText: "好，先加一个 /login 路由。", isUser: true, sequence: 5),
                PocketMessage(demoText: """
                已加好：

                ```ts
                { path: "/login", component: LoginPage }
                ```

                另外在导航栏的「登录」按钮上补了跳转。需要我顺手加个表单校验吗？
                """, isUser: false, sequence: 6)
            ]
        case "demo-2":
            return [
                PocketMessage(demoText: "这张图里是什么？", isUser: true, sequence: 1, localImages: [demoPicture]),
                PocketMessage(demoText: "图片里是一个深蓝色渐变背景上的白色圆形图案，像是某个 App 的图标或占位图。", isUser: false, sequence: 2)
            ]
        default:
            return [
                PocketMessage(demoText: "帮我重构一下 Agent 的上下文拼接逻辑，太长就总结一下。", isUser: true, sequence: 1),
                PocketMessage(demoText: """
                改动思路分三步：

                1. **拆**：把 system prompt、workspace 上下文、会话历史拆成独立 builder；
                2. **合**：统一在 request 组装时按优先级拼接；
                3. **测**：补一个快照测试，固定输入下的输出。

                这样可以避免上下文重复注入，也方便以后按模型做裁剪。
                """, isUser: false, sequence: 2),
                PocketMessage(demoText: "先把第一步做掉，改完给我 diff。", isUser: true, sequence: 3),
                PocketMessage(demoText: """
                已完成三个 builder，保留了旧入口做兼容：

                | 插件 | 形式 | 功能 |
                | --- | --- | --- |
                | chenzhexi/dsh-api-usage | GitHub | 侧边栏常驻小部件：余额、今日消费、Token 数、请求数、24h 消费柱状图，一键直达充值页。 |
                | cailikelog/dsh-plugin-account-balance | GitHub | 在输入框 cache-hit 读数旁显示账户剩余余额 |
                | Witherwithwinter/DeepSeek-Balance-Whale-Widget-Bowl | GitHub | 右下角常驻余额挂件（鲸鱼娘版），支持 DeepSeek、OpenRouter、Kimi、GLM 等多个平台 |
                """, isUser: false, sequence: 4)
            ]
        }
    }

    private static func demoSteps(for sessionId: String) -> [PocketStep] {
        guard sessionId == "demo-1" else { return [] }
        return [
            PocketStep(id: "demo-step-1", sequence: 2, turn: 1, number: 1,
                       name: "bash", detail: "ls -la",
                       resultText: "drwxr-xr-x  12 ruska  staff  384  src\n-rw-r--r--   1 ruska  staff  512  package.json",
                       finished: true),
            PocketStep(id: "demo-step-2", sequence: 3, turn: 1, number: 2,
                       name: "read", detail: "src/router.ts",
                       resultText: "export const routes = [ ... ]", finished: true)
        ]
    }

    @MainActor
    func loadSessions(silently: Bool = false) async {
        if isDemoMode { return }
        guard !isLoadingSessions else { return }
        if !silently { isLoadingSessions = true }
        defer { isLoadingSessions = false }
        do {
            sessions = try await fetchSessions()
            syncSelectedSessionMetadata()
            recordDiagnostic("会话列表刷新：\(sessions.count) 个，隐藏归档 \(archivedSessionIds.count) 个")
        } catch {
            errorMessage = "无法读取会话：\(error.localizedDescription)"
            recordDiagnostic("会话列表刷新失败：\(error.localizedDescription)")
        }
    }

    private func fetchSessions() async throws -> [PocketSession] {
        let value = try await rpc("session/list", args: ["_request": ["excludeArchived": true]])
        let items = value["items"] as? [[String: Any]] ?? []
        let sessions = items.compactMap(PocketSession.init(json:))
        let archived: Set<String>
        if value["archivedSessionsExcluded"] as? Bool == true {
            archived = []
        } else {
            archived = try await fetchArchivedSessionIds()
        }
        archivedSessionIds = archived
        // 与 DSH 桌面端侧边栏保持一致：隐藏已归档、subagent 子会话和空会话，
        // 这样 iOS 列表数量和 Mac 端看到的数量一致。
        return sessions.filter { !archived.contains($0.sessionId) && !$0.isSubagent && !$0.isHiddenFromList }
    }

    private func fetchArchivedSessionIds() async throws -> Set<String> {
        guard let base = try? Self.serverURL(from: serverAddress),
              let socketURL = Self.webSocketURL(from: base, path: "api/remote.mux") else {
            throw ConnectionError.invalidURL(serverAddress)
        }
        let socket = URLSession.shared.webSocketTask(with: socketURL)
        let streamId = UUID().uuidString
        let open = StreamOpen(type: "open", streamId: streamId, endpoint: "workspace/follow", payload: ["args": [:]])
        let timeout = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { socket.cancel(with: .goingAway, reason: nil) }
        }
        defer {
            timeout.cancel()
            socket.cancel(with: .goingAway, reason: nil)
        }
        socket.resume()
        let encoded = try JSONEncoder().encode(open)
        guard let requestText = String(data: encoded, encoding: .utf8) else { throw ConnectionError.invalidPayload }
        try await socket.send(.string(requestText))
        while true {
            let frame = try await socket.receive()
            let data: Data
            switch frame {
            case .data(let bytes): data = bytes
            case .string(let text): data = Data(text.utf8)
            @unknown default: continue
            }
            guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  envelope["streamId"] as? String == streamId,
                  envelope["type"] as? String == "item",
                  let value = envelope["value"] as? [String: Any] else { continue }
            guard value["type"] as? String == "baseline",
                  let baseline = value["value"] as? [String: Any],
                  let archived = baseline["archivedSessionIds"] as? [String] else {
                throw ConnectionError.invalidPayload
            }
            return Set(archived)
        }
    }

    @MainActor
    func createSession() async {
        do {
            var request: [String: Any] = [:]
            if let initialized = try? await rpc("workspace/initializeDefault", args: [:]),
               let workspace = initialized["workspace"] as? [String: Any],
               let workspaceId = workspace["workspaceId"] as? String {
                request["workspaceId"] = workspaceId
            }
            let value = try await rpc("session/create", args: ["request": request])
            guard let id = value["sessionId"] as? String else { throw ConnectionError.invalidPayload }
            let session = PocketSession(sessionId: id, updatedAt: Date().timeIntervalSince1970, running: false, blank: true)
            await loadSessions()
            if !sessions.contains(where: { $0.sessionId == id }) { sessions.insert(session, at: 0) }
            open(session)
        } catch {
            errorMessage = "无法创建会话：\(error.localizedDescription)"
        }
    }

    @MainActor
    func open(_ session: PocketSession) {
        if isDemoMode { openDemo(session); return }
        if selectedSession?.sessionId == session.sessionId, liveTask != nil { return }
        liveTask?.cancel()
        fallbackTask?.cancel()
        selectedSession = session
        liveConnectionState = "正在连接"
        messages = []
        steps = []
        isTurnRunning = false
        turnStartedAt = nil
        conversationError = nil
        recordDiagnostic("打开会话：\(session.displayTitle)")
        liveTask = Task { await loadConversation(session) }
    }

    @MainActor
    private func loadConversation(_ session: PocketSession) async {
        isLoadingConversation = true
        // 历史上限走 HTTP 分页：公网隧道可能限制 WebSocket 单帧大小，
        // 不能只依赖 follow 的首帧快照。
        fallbackTask?.cancel()
        fallbackTask = Task { await pollLiveFallback(session) }
        let historyTask = Task { await self.loadHistory(session) }
        await follow(session)
        _ = await historyTask.value
        if selectedSession?.sessionId == session.sessionId, isLoadingConversation {
            isLoadingConversation = false
        }
    }

    /// 实时流不可用（例如公网代理拒绝大帧）时，用 HTTP 分页轮询兜底，保证新消息仍能出现。
    @MainActor
    private func pollLiveFallback(_ session: PocketSession) async {
        while !Task.isCancelled, selectedSession?.sessionId == session.sessionId {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { break }
            guard selectedSession?.sessionId == session.sessionId else { return }
            if liveConnectionState != "已连接" {
                await loadHistory(session)
            }
        }
    }

    @MainActor
    private func loadHistory(_ session: PocketSession) async {
        do {
            let address: [String: Any] = ["kind": "session", "sessionId": session.sessionId]
            let page = try await rpc("session/page", args: ["request": ["address": address, "maxMessages": Self.conversationMessageLimit]])
            guard selectedSession?.sessionId == session.sessionId else { return }
            let records = page["records"] as? [[String: Any]] ?? []
            let history = records.compactMap(PocketMessage.init(record:))
            mergeMessages(history)
            mergeSteps(from: records)
            isLoadingConversation = false
        } catch {
            if error is CancellationError { return }
            guard selectedSession?.sessionId == session.sessionId, messages.isEmpty else { return }
            conversationError = "无法读取历史对话：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func mergeMessages(_ incoming: [PocketMessage]) {
        var bySequence = Dictionary(uniqueKeysWithValues: messages.filter { !$0.isPending }.map { ($0.sequence, $0) })
        for message in incoming where !message.isPending { bySequence[message.sequence] = message }
        let incomingUserTexts = Set(incoming.filter(\.isUser).map(\.text))
        let pending = messages.filter { $0.isPending && !incomingUserTexts.contains($0.text) }
        messages = (Array(bySequence.values) + pending).sorted { $0.sequence < $1.sequence }
        timingLog("model_update incoming=\(incoming.count) total=\(messages.count)")
    }

    /// 会话页标题：优先用列表中最新标题，避免打开后改标题不刷新。
    var currentConversationTitle: String {
        guard let id = selectedSession?.sessionId else { return "对话" }
        return (sessions.first(where: { $0.sessionId == id }) ?? selectedSession)?.displayTitle ?? "对话"
    }

    @MainActor
    private func updateSessionTitle(_ title: String) {
        guard let id = selectedSession?.sessionId else { return }
        if let index = sessions.firstIndex(where: { $0.sessionId == id }) {
            sessions[index] = sessions[index].withTitle(title)
        }
        if let current = selectedSession {
            selectedSession = current.withTitle(title)
        }
    }

    /// 列表刷新后，把已打开会话的标题/运行状态同步过来。
    @MainActor
    private func syncSelectedSessionMetadata() {
        guard let id = selectedSession?.sessionId,
              let fresh = sessions.first(where: { $0.sessionId == id }) else { return }
        selectedSession = fresh
    }

    /// 按 turn 分组的工具步骤，供会话页折叠成"过程"一行。
    var stepGroups: [PocketStepGroup] {
        Dictionary(grouping: steps, by: \.turn)
            .map { turn, list in
                PocketStepGroup(turn: turn, sequence: list.map(\.sequence).min() ?? 0,
                                steps: list.sorted { $0.sequence < $1.sequence })
            }
            .sorted { $0.sequence < $1.sequence }
    }

    @MainActor
    private func mergeSteps(from records: [[String: Any]]) {
        for record in records {
            guard let event = record["event"] as? [String: Any] else { continue }
            applyStepEvent(event)
        }
    }

    /// 处理 tool/call、tool/result、turn/start、turn/end 等过程事件。
    @MainActor
    func applyStepEvent(_ event: [String: Any]) {
        guard let type = event["type"] as? String,
              let sequence = (event["seq"] as? NSNumber)?.intValue else { return }
        let data = event["data"] as? [String: Any] ?? [:]
        switch type {
        case "tool/call":
            guard let callId = data["callId"] as? String,
                  let name = data["name"] as? String else { return }
            guard !steps.contains(where: { $0.id == callId }) else { return }
            let turn = (data["turn"] as? NSNumber)?.intValue ?? 0
            let number = (data["step"] as? NSNumber)?.intValue ?? 0
            let arguments = (data["arguments"] as? String).flatMap {
                try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
            } ?? [:]
            let step = PocketStep(id: callId, sequence: sequence, turn: turn, number: number,
                                  name: name, detail: Self.stepDetail(name: name, arguments: arguments))
            steps.append(step)
            steps.sort { $0.sequence < $1.sequence }
            recordDiagnostic("过程：\(step.label)\(step.detail.isEmpty ? "" : "（\(step.detail)）")")
        case "tool/result":
            let message = data["message"] as? [String: Any] ?? [:]
            guard let callId = (message["toolCallId"] as? String) ?? (data["callId"] as? String),
                  let index = steps.firstIndex(where: { $0.id == callId }) else { return }
            let content = message["content"] as? [[String: Any]] ?? []
            steps[index].resultText = content.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }.joined()
            steps[index].images = content.compactMap { block -> PocketImageRef? in
                guard block["type"] as? String == "image",
                      let attachment = block["attachment"] as? [String: Any] else { return nil }
                return PocketImageRef(json: attachment)
            }
            steps[index].isError = message["isError"] as? Bool ?? false
            steps[index].finished = true
        case "turn/start":
            isTurnRunning = true
            let time = (event["time"] as? NSNumber)?.doubleValue ?? 0
            turnStartedAt = time > 0 ? Date(timeIntervalSince1970: time / 1000) : Date()
        case "turn/end":
            isTurnRunning = false
        case "session/title":
            if let title = data["title"] as? String, !title.isEmpty {
                updateSessionTitle(title)
            }
        default:
            break
        }
    }

    private static func stepDetail(name: String, arguments: [String: Any]) -> String {
        switch name {
        case "bash":
            let command = (arguments["command"] as? String) ?? ""
            let first = command.split(separator: "\n").first.map(String.init) ?? command
            return String(first.prefix(80))
        case "read", "read_image", "write", "edit":
            guard let path = arguments["file_path"] as? String else { return "" }
            return URL(fileURLWithPath: path).lastPathComponent
        case "web_search":
            return (arguments["queries"] as? [String])?.joined(separator: " / ").prefix(80).description ?? ""
        case "web_fetch":
            return (arguments["url"] as? String) ?? ""
        case "ask_user_question":
            return "等待你的回答"
        default:
            return ""
        }
    }

    /// 读取电脑端附件库里的图片（带内存缓存）。
    @MainActor
    func loadImage(_ ref: PocketImageRef) async -> UIImage? {
        if let cached = Self.imageCache[ref.attachmentId] { return cached }
        guard let session = selectedSession else { return nil }
        do {
            let value = try await rpc("session/attachment", args: ["request": [
                "sessionId": session.sessionId,
                "attachment": ref.requestJSON
            ]])
            guard let base64 = value["data"] as? String,
                  let data = Data(base64Encoded: base64),
                  let image = UIImage(data: data) else { return nil }
            Self.imageCache[ref.attachmentId] = image
            return image
        } catch {
            return nil
        }
    }

    /// 把照片/相机图片压缩成待发送附件。
    @MainActor
    func addDraftImage(_ image: UIImage) {
        guard let prepared = Self.prepareImage(image) else { return }
        draftImages.append(prepared)
    }

    static func prepareImage(_ image: UIImage) -> PocketDraftImage? {
        let maxSide: CGFloat = 2048
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return nil }
        return PocketDraftImage(data: data, mediaType: "image/jpeg",
                                name: "photo-\(Int(Date().timeIntervalSince1970)).jpg", uiImage: resized)
    }

    @MainActor
    private func pollForReply(_ session: PocketSession, after text: String, afterSequence: Int) async {
        let started = Date()
        timingLog("history_poll_start text=\(text.debugDescription)")
        for _ in 0..<30 {
            if Task.isCancelled { return }
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }
            guard selectedSession?.sessionId == session.sessionId else { return }
            // 实时 follow 已经把回复送到时就不必再轮询分页了；轮询只作为断流兜底。
            if messages.contains(where: { !$0.isUser && !$0.isPending && $0.sequence > afterSequence }) {
                timingLog("reply_available source=follow total_elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                return
            }
            do {
                let address: [String: Any] = ["kind": "session", "sessionId": session.sessionId]
                let page = try await rpc("session/page", args: ["request": ["address": address, "maxMessages": Self.conversationMessageLimit]])
                let records = page["records"] as? [[String: Any]] ?? []
                let incoming = records.compactMap(PocketMessage.init(record:))
                timingLog("history_poll_result messages=\(incoming.count) elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                mergeMessages(incoming)
                mergeSteps(from: records)
                if let reply = incoming.first(where: { !$0.isUser && !$0.isPending && $0.sequence > afterSequence }) {
                    timingLog("reply_available source=history seq=\(reply.sequence) chars=\(reply.text.count) total_elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                    recordDiagnostic("历史轮询找到本次助手回复，等待 \(Int(Date().timeIntervalSince(started) * 1000)) 毫秒；内容：\(reply.text)")
                    return
                }
            } catch { }
        }
        recordDiagnostic("历史轮询超时：30 次内未找到本次助手回复")
    }

    @MainActor
    private func follow(_ session: PocketSession) async {
        if isDemoMode { return }
        guard let base = URL(string: serverAddress),
              let socketURL = Self.webSocketURL(from: base, path: "api/remote.mux") else {
            recordDiagnostic("实时连接未启动：地址无效 \(serverAddress.debugDescription)")
            return
        }
        var retryDelay: Duration = .seconds(1)
        var receivedSnapshot = false
        var usedHistoryFallback = false
        while !Task.isCancelled, selectedSession?.sessionId == session.sessionId {
            liveConnectionState = "正在连接"
            let socket = URLSession.shared.webSocketTask(with: socketURL)
            socket.resume()
            recordDiagnostic("实时连接：发起连接")
            pocketLogger.info("follow connecting session=\(session.sessionId, privacy: .public) url=\(socketURL.absoluteString, privacy: .private)")
            let streamId = UUID().uuidString
            let open = StreamOpen(type: "open", streamId: streamId, endpoint: "session/follow", payload: ["args": ["request": ["address": ["kind": "session", "sessionId": session.sessionId], "maxMessages": Self.conversationMessageLimit]]])
            do {
                let data = try JSONEncoder().encode(open)
                guard let text = String(data: data, encoding: .utf8) else { throw ConnectionError.invalidPayload }
                try await socket.send(.string(text))
                let heartbeat = Task {
                    while !Task.isCancelled {
                        do {
                            try await Task.sleep(for: .seconds(25))
                            try await sendPing(socket)
                        } catch {
                            if !Task.isCancelled { socket.cancel(with: .abnormalClosure, reason: nil) }
                            return
                        }
                    }
                }
                defer { heartbeat.cancel() }
                while !Task.isCancelled {
                    let frame = try await withTaskCancellationHandler {
                        try await socket.receive()
                    } onCancel: {
                        socket.cancel(with: .goingAway, reason: nil)
                    }
                    let data: Data
                    switch frame {
                    case .data(let received): data = received
                    case .string(let text): data = Data(text.utf8)
                    @unknown default: continue
                    }
                    NSLog("DSH_DIAG websocket frame bytes=%ld", data.count)
                    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          object["streamId"] as? String == streamId,
                          object["type"] as? String == "item",
                          let value = object["value"] as? [String: Any] else {
                        NSLog("DSH_DIAG ignored frame keys=%@ type=%@ streamMatch=%@", (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?.keys.sorted().joined(separator: ",") ?? "invalid", ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["type"] as? String) ?? "nil", (((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["streamId"] as? String) == streamId) ? "yes" : "no")
                        continue
                    }
                    let valueType = value["type"] as? String ?? "未知"
                    if valueType == "snapshot" { receivedSnapshot = true }
                    liveConnectionState = "已连接"
                    if conversationError?.hasPrefix("实时连接") == true { conversationError = nil }
                    retryDelay = .seconds(1)
                    pocketLogger.info("follow item valueType=\(valueType, privacy: .public) keys=\(value.keys.sorted().joined(separator: ","), privacy: .public)")
                    acceptLive(value, sessionId: session.sessionId)
                }
                if !Task.isCancelled { throw ConnectionError.remote("实时连接已结束") }
            } catch {
                socket.cancel(with: .goingAway, reason: nil)
                guard !Task.isCancelled else { break }
                liveConnectionState = "正在重连"
                conversationError = "实时连接中断，正在重连：\(error.localizedDescription)"
                recordDiagnostic("实时连接中断，\(Int(retryDelay.components.seconds)) 秒后重试：\(error.localizedDescription)")
                pocketLogger.error("follow failed: \(error.localizedDescription, privacy: .public)")
                if !receivedSnapshot && !usedHistoryFallback {
                    usedHistoryFallback = true
                    await loadHistory(session)
                }
                do { try await Task.sleep(for: retryDelay) } catch { break }
                retryDelay = min(retryDelay * 2, .seconds(15))
            }
        }
        if selectedSession?.sessionId == session.sessionId { liveConnectionState = "已断开" }
    }

    @MainActor
    private func acceptLive(_ value: [String: Any], sessionId: String) {
        guard selectedSession?.sessionId == sessionId else { return }
        if value["type"] as? String == "snapshot" {
            let records = value["records"] as? [[String: Any]] ?? []
            let history = records.compactMap(PocketMessage.init(record:))
            mergeMessages(history)
            mergeSteps(from: records)
            recordDiagnostic("收到历史快照：\(history.count) 条消息")
            isLoadingConversation = false
        } else if let event = value["event"] as? [String: Any] {
            if let message = PocketMessage(event: event) {
                pocketLogger.info("follow message kind=\(message.kind, privacy: .public) seq=\(message.sequence) chars=\(message.text.count)")
                if let pendingIndex = messages.firstIndex(where: { $0.isPending && $0.isUser && $0.text == message.text }) {
                    messages.remove(at: pendingIndex)
                }
                if !messages.contains(where: { !$0.isPending && $0.sequence == message.sequence }) {
                    messages.append(message)
                    messages.sort { $0.sequence < $1.sequence }
                }
                timingLog("reply_available source=follow kind=\(message.kind) seq=\(message.sequence) chars=\(message.text.count) total_messages=\(messages.count)")
                recordDiagnostic("实时收到\(message.isUser ? "用户" : "助手")消息，序号 \(message.sequence)，\(message.text.count) 字")
            } else {
                // 工具步骤、turn 起止等过程事件
                applyStepEvent(event)
                let eventType = event["type"] as? String
                let eventData = event["data"] as? [String: Any]
                let sourceKind = (eventData?["source"] as? [String: Any])?["kind"] as? String
                if eventType == "assistant/message" || (eventType == "user/message" && sourceKind == "user") {
                    recordDiagnostic("消息事件未解析：\(eventType ?? "未知")，source=\(sourceKind ?? "-")")
                }
            }
        } else {
            recordDiagnostic("未识别 follow 数据：\(value.keys.sorted().joined(separator: ","))")
        }
    }

    private func sendPing(_ socket: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.sendPing { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    @MainActor
    func sendMessage() {
        if isSending { return }
        if isDemoMode {
            sendTask = Task { await self.sendDemoMessage() }
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = draftImages
        guard (!text.isEmpty || !attachments.isEmpty), selectedSession != nil else { return }
        sendTask?.cancel()
        sendTask = Task { await self.performSend(text: text, attachments: attachments) }
    }

    /// 取消"发送中"的消息：撤回本地待确认气泡，恢复输入内容。
    @MainActor
    func cancelSend() {
        guard isSending else { return }
        sendTask?.cancel()
        sendTask = nil
        if let id = pendingSendID { messages.removeAll { $0.id == id } }
        pendingSendID = nil
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft = cancelledDraft
            draftImages = cancelledImages
        }
        cancelledDraft = ""
        cancelledImages = []
        isSending = false
        conversationError = nil
        recordDiagnostic("已取消发送")
    }

    /// 停止当前这一轮生成（消息已发出、正在等回复时使用）。
    @MainActor
    func cancelTurn() async {
        guard let session = selectedSession, !isDemoMode else { return }
        do {
            _ = try await rpc("session/cancel", args: ["request": ["sessionId": session.sessionId]])
            isTurnRunning = false
            recordDiagnostic("已请求停止当前生成")
        } catch {
            conversationError = "停止失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func performSend(text: String, attachments: [PocketDraftImage]) async {
        guard let session = selectedSession, !isSending else { return }
        let lastSequence = messages.filter { !$0.isPending }.map(\.sequence).max() ?? -1
        let pending = PocketMessage(pendingText: text, localImages: attachments.map(\.uiImage))
        let sendStarted = Date()
        timingLog("send_typed chars=\(text.count) images=\(attachments.count)")
        recordDiagnostic("用户点击发送：\(text.count) 字，图片 \(attachments.count) 张")
        messages.append(pending)
        pendingSendID = pending.id
        cancelledDraft = text
        cancelledImages = attachments
        draft = ""
        draftImages = []
        isSending = true
        defer {
            isSending = false
            pendingSendID = nil
            cancelledDraft = ""
            cancelledImages = []
        }
        do {
            timingLog("prompt_start chars=\(text.count) images=\(attachments.count)")
            var content: [[String: Any]] = []
            if !text.isEmpty { content.append(["type": "text", "text": text]) }
            for image in attachments {
                content.append([
                    "type": "image",
                    "mediaType": image.mediaType,
                    "data": image.data.base64EncodedString(),
                    "name": image.name
                ])
            }
            _ = try await rpc("session/prompt", args: ["request": [
                "requestId": UUID().uuidString,
                "sessionId": session.sessionId,
                "mode": "queue",
                "content": content,
                "clientTimeZone": TimeZone.current.identifier
            ]])
            timingLog("prompt_ack elapsed_ms=\(Int(Date().timeIntervalSince(sendStarted) * 1000))")
            recordDiagnostic("服务端已确认发送，耗时 \(Int(Date().timeIntervalSince(sendStarted) * 1000)) 毫秒")
            conversationError = nil
            // 服务端已受理：立刻结束"发送中"状态，恢复发送按钮；后续等待回复交给轮询与停止按钮。
            isSending = false
            pendingSendID = nil
            cancelledDraft = ""
            cancelledImages = []
            // 先用服务端真实用户消息替换本地待确认消息，保证"用户消息在上、助手回复在下"的顺序；
            // 否则实时回复先到、轮询提前退出时，待确认消息会带着临时序号排在回复后面。
            await loadHistory(session)
            await pollForReply(session, after: text, afterSequence: lastSequence)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            messages.removeAll { $0.id == pending.id }
            draft = text
            draftImages = attachments
            conversationError = "发送失败：\(error.localizedDescription)"
        }
    }

    private func rpc(_ endpoint: String, args: [String: Any]) async throws -> [String: Any] {
        let root = try Self.serverURL(from: serverAddress)
        let url = root.appending(path: "api/\(endpoint)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpShouldHandleCookies = true
        let requestBody: [String: Any] = ["type": "client-request", "rpcId": UUID().uuidString, "method": endpoint, "payload": ["args": args]]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ConnectionError.server((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = envelope["result"] as? [String: Any] else { throw ConnectionError.invalidPayload }
        if result["ok"] as? Bool == false {
            let error = result["error"] as? [String: Any]
            throw ConnectionError.remote(error?["message"] as? String ?? "DSH 请求失败")
        }
        return result["value"] as? [String: Any] ?? [:]
    }
}

struct PocketSession: Identifiable, Hashable {
    let sessionId: String
    let updatedAt: TimeInterval
    let running: Bool
    let blank: Bool
    let title: String?
    let cwd: String?
    let origin: String?
    let parentSessionId: String?
    var id: String { sessionId }

    init(sessionId: String, updatedAt: TimeInterval, running: Bool, blank: Bool, title: String? = nil, cwd: String? = nil, origin: String? = nil, parentSessionId: String? = nil) {
        self.sessionId = sessionId
        self.updatedAt = updatedAt
        self.running = running
        self.blank = blank
        self.title = title
        self.cwd = cwd
        self.origin = origin
        self.parentSessionId = parentSessionId
    }

    init?(json: [String: Any]) {
        guard let id = json["sessionId"] as? String else { return nil }
        let projection = json["projections"] as? [String: Any]
        let values = projection?["values"] as? [String: Any]
        let title = values?["title"] as? String
        self.init(sessionId: id, updatedAt: json["updatedAt"] as? TimeInterval ?? 0,
                  running: json["running"] as? Bool ?? false, blank: json["blank"] as? Bool ?? false,
                  title: title, cwd: json["cwd"] as? String,
                  origin: json["origin"] as? String, parentSessionId: json["parentSessionId"] as? String)
    }

    func withTitle(_ title: String) -> PocketSession {
        PocketSession(sessionId: sessionId, updatedAt: updatedAt, running: running, blank: blank,
                      title: title, cwd: cwd, origin: origin, parentSessionId: parentSessionId)
    }

    /// DSH 桌面端侧边栏不显示 subagent 子会话和空会话，iOS 保持同样的可见性规则。
    var isSubagent: Bool { origin == "subagent" || parentSessionId != nil }
    var isHiddenFromList: Bool { blank || (title?.isEmpty ?? true) }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if blank { return "新会话" }
        if let cwd {
            let name = URL(fileURLWithPath: cwd).lastPathComponent
            if !name.isEmpty { return name }
        }
        return "未命名会话"
    }
}

struct PocketMessage: Identifiable {
    let id: String
    let sequence: Int
    let kind: String
    let text: String
    let isUser: Bool
    let isPending: Bool
    let images: [PocketImageRef]
    let localImages: [UIImage]

    init(demoText: String, isUser: Bool, sequence: Int, localImages: [UIImage] = []) {
        self.id = "demo-\(sequence)"
        self.sequence = sequence
        self.kind = isUser ? "user/message" : "assistant/message"
        self.text = demoText
        self.isUser = isUser
        self.isPending = false
        self.images = []
        self.localImages = localImages
    }

    init(pendingText: String, localImages: [UIImage] = []) {
        self.id = "pending-\(UUID().uuidString)"
        self.sequence = Int.max
        self.kind = "user/message"
        self.text = pendingText
        self.isUser = true
        self.isPending = true
        self.images = []
        self.localImages = localImages
    }

    init?(record: [String: Any]) {
        guard let event = record["event"] as? [String: Any] else { return nil }
        self.init(event: event)
    }

    init?(event: [String: Any]) {
        guard let kind = event["type"] as? String,
              ["user/message", "assistant/message"].contains(kind),
              let sequence = (event["seq"] as? NSNumber)?.intValue,
              let data = event["data"] as? [String: Any] else { return nil }
        let message = (data["message"] as? [String: Any]) ?? data
        // DSH also stores injected runtime context as user/message events. Those
        // are model inputs, not messages the human sent, and must stay out of chat UI.
        if kind == "user/message" {
            let source = (message["source"] as? [String: Any]) ?? (data["source"] as? [String: Any])
            guard source?["kind"] as? String == "user" else { return nil }
        }
        let content = message["content"] as? [[String: Any]] ?? []
        let text = content.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }.joined()
        let images = content.compactMap { block -> PocketImageRef? in
            guard block["type"] as? String == "image",
                  let attachment = block["attachment"] as? [String: Any] else { return nil }
            return PocketImageRef(json: attachment)
        }
        guard !text.isEmpty || !images.isEmpty else { return nil }
        self.id = "event-\(sequence)"
        self.sequence = sequence
        self.kind = kind
        self.text = text
        self.isUser = kind == "user/message"
        self.isPending = false
        self.images = images
        self.localImages = []
    }
}

/// 一张已落到电脑端附件库的图片引用（会话历史 / 工具结果里的图片）。
struct PocketImageRef: Identifiable, Hashable {
    let attachmentId: String
    let mediaType: String
    let bytes: Int
    let width: Int
    let height: Int
    let name: String?
    var id: String { attachmentId }

    init?(json: [String: Any]) {
        guard let attachmentId = json["attachmentId"] as? String else { return nil }
        self.attachmentId = attachmentId
        self.mediaType = json["mediaType"] as? String ?? "image/jpeg"
        self.bytes = (json["bytes"] as? NSNumber)?.intValue ?? 0
        self.width = (json["width"] as? NSNumber)?.intValue ?? 0
        self.height = (json["height"] as? NSNumber)?.intValue ?? 0
        self.name = json["name"] as? String
    }

    var requestJSON: [String: Any] {
        var value: [String: Any] = ["attachmentId": attachmentId, "mediaType": mediaType]
        if bytes > 0 { value["bytes"] = bytes }
        if width > 0 { value["width"] = width }
        if height > 0 { value["height"] = height }
        if let name, !name.isEmpty { value["name"] = name }
        return value
    }
}

/// 待发送的本地图片（照片库 / 相机）。
struct PocketDraftImage: Identifiable {
    let id = UUID()
    let data: Data
    let mediaType: String
    let name: String
    let uiImage: UIImage
}

/// 一轮里的一个工具调用步骤（对应 Mac 端"执行了命令 / 查看了图片"那一行）。
struct PocketStep: Identifiable {
    let id: String
    let sequence: Int
    let turn: Int
    let number: Int
    let name: String
    let detail: String
    var resultText = ""
    var isError = false
    var finished = false
    var images: [PocketImageRef] = []

    var label: String {
        switch name {
        case "bash": "执行了命令"
        case "read": "读取了文件"
        case "read_image": "查看了图片"
        case "edit": "编辑了文件"
        case "write": "写入了文件"
        case "web_search": "搜索了网页"
        case "web_fetch": "抓取了网页"
        case "job_output": "读取了任务输出"
        case "todo_write": "更新了待办"
        case "ask_user_question": "向你确认问题"
        default: name
        }
    }

    var icon: String {
        switch name {
        case "bash": "terminal"
        case "read", "read_image": "doc.text.magnifyingglass"
        case "edit", "write": "square.and.pencil"
        case "web_search", "web_fetch": "globe"
        case "todo_write": "checklist"
        case "ask_user_question": "questionmark.bubble"
        default: "gearshape"
        }
    }
}

/// 同一 turn 内的一组步骤，UI 里折叠成一行"过程"。
struct PocketStepGroup: Identifiable {
    let turn: Int
    let sequence: Int
    let steps: [PocketStep]
    var id: Int { turn }
}

private struct StreamOpen: Encodable {
    let type: String
    let streamId: String
    let endpoint: String
    let payload: [String: AnyEncodable]

    init(type: String, streamId: String, endpoint: String, payload: [String: Any]) {
        self.type = type
        self.streamId = streamId
        self.endpoint = endpoint
        self.payload = payload.mapValues(AnyEncodable.init)
    }
}

private struct AnyEncodable: Encodable {
    private let value: Any
    init(_ value: Any) { self.value = value }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value = value as? String { try container.encode(value) }
        else if let value = value as? Int { try container.encode(value) }
        else if let value = value as? Bool { try container.encode(value) }
        else if let value = value as? [String: Any] { try container.encode(value.mapValues(AnyEncodable.init)) }
        else if let value = value as? [Any] { try container.encode(value.map(AnyEncodable.init)) }
        else { try container.encodeNil() }
    }
}

enum ConnectionError: LocalizedError {
    case invalidPin, unexpectedResponse, invalidPayload, invalidURL(String), server(Int), rateLimited(Int), remote(String)
    var errorDescription: String? {
        switch self {
        case .invalidPin: "密码不正确，请检查后重试。"
        case .unexpectedResponse: "服务器返回了无法识别的响应。"
        case .invalidPayload: "服务器响应格式无效。"
        case .invalidURL(let raw): "地址格式无效：\(raw.debugDescription)。请输入 http://192.0.2.10:3081 这样的地址。"
        case .server(let code): "服务器暂时无法连接（HTTP \(code)）。"
        case .rateLimited(let seconds): "尝试次数过多，请 \(max(seconds, 1)) 秒后再试。"
        case .remote(let message): message
        }
    }
}

/// 只用来记录登录请求是否发生过重定向，重定向本身仍然跟随。
private final class LoginRedirectRecorder: NSObject, URLSessionTaskDelegate {
    private(set) var redirected = false

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirected = true
        completionHandler(request)
    }
}

/// 仅 Debug 生效的自测入口，方便在真机/模拟器上自动连接与复现：
/// --dsh-server http://192.0.2.10:3081 --dsh-pin 12345678 --dsh-open <sessionId> --dsh-send 文本
#if DEBUG
enum DebugLaunch {
    static var server: String? { environment["DSH_SERVER"] ?? value(for: "--dsh-server") }
    static var pin: String? { environment["DSH_PIN"] ?? value(for: "--dsh-pin") }
    static var sessionId: String? { environment["DSH_OPEN"] ?? value(for: "--dsh-open") }
    static var sendText: String? { environment["DSH_SEND"] ?? value(for: "--dsh-send") }
    static var showConnect: Bool { environment["DSH_CONNECT"] == "1" }
    static var attachPath: String? { environment["DSH_ATTACH"] ?? value(for: "--dsh-attach") }
    static var demoMode: Bool { environment["DSH_DEMO"] == "1" }

    /// 模拟器用 `SIMCTL_CHILD_DSH_SERVER`，真机用 `DEVICECTL_CHILD_DSH_SERVER`，
    /// 由 simctl / devicectl 去掉前缀后注入进程环境。
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    private static func value(for key: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: key), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
#endif

struct RootView: View {
    @Bindable var model: ConnectionModel
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack(path: $model.navigationPath) {
            Group {
                if model.isConnected {
                    ConnectedView(model: model)
                } else {
                    ConnectView(model: model)
                }
            }
            .navigationTitle("DSH Pocket")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Color(red: 0.08, green: 0.48, blue: 0.37))
        .task { await model.restoreConnection() }
        .onChange(of: scenePhase) { _, phase in
            // 回到前台时静默刷新列表：在电脑上归档的会话会同步消失，不用手动下拉。
            guard phase == .active, model.isConnected else { return }
            Task { await model.loadSessions(silently: true) }
        }
    }
}

struct ConnectView: View {
    @Bindable var model: ConnectionModel
    @State private var showingScanner = false
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 28, weight: .medium)).foregroundStyle(.green).frame(width: 48, height: 48).background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("连接你的 DSH").font(.headline)
                        Text("输入电脑上的 DSH Pocket 地址和访问密码").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8).listRowBackground(Color.clear)
            }
            Section("主机") {
                HStack(spacing: 10) {
                    TextField("http://192.168.1.10:3081", text: $model.serverAddress).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.URL)
                    Button { showingScanner = true } label: { Image(systemName: "qrcode.viewfinder").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44) }.buttonStyle(.bordered).accessibilityLabel("扫描 Pocket 二维码")
                }
                SecureField("访问密码", text: $model.pin).textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            if let error = model.errorMessage { Section { Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red).font(.subheadline) } }
            Section {
                Button { Task { await model.connect() } } label: {
                    HStack { Spacer(); if model.isConnecting { ProgressView().padding(.trailing, 6); Text("正在连接") } else { Image(systemName: "arrow.right.circle.fill"); Text("连接") }; Spacer() }.fontWeight(.semibold)
                }.disabled(model.isConnecting)
            }
            Section {
                Button { model.startDemoMode() } label: {
                    HStack { Spacer(); Image(systemName: "play.circle"); Text("体验演示模式"); Spacer() }
                }
                .accessibilityHint("没有电脑时查看内置示例会话与对话")
            } footer: {
                Text("演示模式使用内置示例数据，不会连接或发送任何内容。")
            }
        }
        .onAppear { model.errorMessage = nil }
        .onChange(of: model.serverAddress) { _, _ in model.errorMessage = nil }
        .sheet(isPresented: $showingScanner) {
            NavigationStack {
                QRScannerView { value in if model.useScannedAddress(value) { showingScanner = false } }
                    .navigationTitle("扫描二维码").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showingScanner = false } } }
            }
        }
    }
}

struct QRScannerView: View {
    let onCode: (String) -> Void
    var body: some View {
        Group {
            if DataScannerViewController.isSupported {
                if DataScannerViewController.isAvailable { PocketCodeScanner(onCode: onCode).ignoresSafeArea(edges: .bottom) }
                else { ContentUnavailableView("相机暂不可用", systemImage: "camera.fill", description: Text("请在设置中允许 DSH Pocket 使用相机，然后重试。")) }
            } else { ContentUnavailableView("此设备不支持扫码", systemImage: "qrcode", description: Text("请手动输入 DSH Pocket 地址。")) }
        }
    }
}

struct PocketCodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                guard case .barcode(let barcode) = item, let value = barcode.payloadStringValue else { continue }
                onCode(value)
                dataScanner.stopScanning()
                return
            }
        }
    }
}

struct ConnectedView: View {
    @Bindable var model: ConnectionModel
    @State private var didAutoOpen = false
    var body: some View {
        List {
            if model.isDemoMode {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("演示模式").font(.footnote.weight(.semibold))
                            Text("示例数据，未连接电脑").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("退出") { model.exitDemoMode() }.font(.footnote)
                    }
                }
            }
            if let error = model.errorMessage {
                Section { Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red) }
            }
            if model.sessions.isEmpty && !model.isLoadingSessions {
                ContentUnavailableView("还没有会话", systemImage: "bubble.left.and.bubble.right", description: Text("创建会话后即可开始对话。"))
                    .listRowSeparator(.hidden)
            }
            ForEach(model.sessions) { session in
                NavigationLink(value: session) {
                    HStack(spacing: 12) {
                        Image(systemName: session.running ? "ellipsis.bubble.fill" : "bubble.left").foregroundStyle(session.running ? .green : .secondary).frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.displayTitle).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                            Text(session.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? (session.running ? "正在运行" : "对话记录"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if session.running { Circle().fill(.green).frame(width: 7, height: 7) }
                    }.padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
        .overlay { if model.isLoadingSessions { ProgressView() } }
        .refreshable { await model.loadSessions() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if model.isDemoMode {
                    Button { model.exitDemoMode() } label: { Image(systemName: "play.circle.fill") }.accessibilityLabel("退出演示模式")
                } else {
                    Button { model.disconnect() } label: { Image(systemName: "rectangle.portrait.and.arrow.right") }.accessibilityLabel("断开连接")
                }
            }
            ToolbarItem(placement: .topBarTrailing) { Button { Task { await model.createSession() } } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("新建会话") }
        }
        .navigationTitle("会话")
        .navigationDestination(for: PocketSession.self) { session in
            ConversationView(model: model)
                .onAppear { model.open(session) }
        }
        .task {
            await model.loadSessions(silently: !model.sessions.isEmpty)
#if DEBUG
            if !didAutoOpen, let id = DebugLaunch.sessionId,
               let session = model.sessions.first(where: { $0.sessionId == id }) {
                didAutoOpen = true
                model.navigationPath = [session]
            }
#endif
        }
    }
}

struct MarkdownBody: View {
    let text: String
    @State private var availableWidth: CGFloat = 0

    private enum Block {
        case paragraph(String)
        case heading(String)
        case bullet(String)
        case numbered(String, String)
        case code(String)
        case table(headers: [String], rows: [[String]])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let value):
                    Text(inline(value)).font(.body).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                case .heading(let value):
                    Text(inline(value)).font(.headline).fixedSize(horizontal: false, vertical: true)
                case .bullet(let value):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").font(.body)
                        Text(inline(value)).font(.body).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                case .numbered(let marker, let value):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker).font(.body).foregroundStyle(.secondary)
                        Text(inline(value)).font(.body).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                case .code(let value):
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(value)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                case .table(let headers, let rows):
                    table(headers: headers, rows: rows)
                }
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { availableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in availableWidth = newWidth }
            }
        )
    }

    /// GFM 表格：用 Grid 共享列宽保证对齐，单元格自动换行并铺满气泡宽度。
    private func table(headers: [String], rows: [[String]]) -> some View {
        let columnCount = max(headers.count, rows.map(\.count).max() ?? 0)
        let headerColor = Color.primary.opacity(0.07)
        let separator = Color.primary.opacity(0.12)

        let measuredWidth = availableWidth > 0 ? availableWidth : 320
        let minColumnWidth: CGFloat = 110
        let fits = measuredWidth >= CGFloat(columnCount) * minColumnWidth
        let columnWidth = fits ? measuredWidth / CGFloat(columnCount) : minColumnWidth

        func cell(_ value: String, bold: Bool, background: Color) -> some View {
            Text(inline(value))
                .font(bold ? .footnote.weight(.semibold) : .footnote)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, bold ? 8 : 7)
                .frame(width: columnWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .background(background)
                .overlay(alignment: .bottom) { Rectangle().fill(separator).frame(height: 0.5) }
                .overlay(alignment: .trailing) { Rectangle().fill(separator).frame(width: 0.5) }
        }

        func makeRow(_ values: [String], bold: Bool, background: Color) -> some View {
            HStack(alignment: .top, spacing: 0) {
                ForEach(0..<columnCount, id: \.self) { column in
                    cell(column < values.count ? values[column] : "",
                         bold: bold,
                         background: background)
                }
            }
        }

        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                makeRow(headers, bold: true, background: headerColor)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    makeRow(row, bold: false,
                            background: index % 2 == 1 ? Color.primary.opacity(0.03) : Color.clear)
                }
            }
            .frame(width: CGFloat(columnCount) * columnWidth, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ value: String) -> AttributedString {
        (try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(value)
    }

    /// 按空行/列表/代码块/表格切段。段内保留逐行换行，这是"多行回复能正常换行"的关键。
    private var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var insideCode = false
        let lines = text.components(separatedBy: "\n")
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            result.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        while index < lines.count {
            let rawLine = lines[index]
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if insideCode {
                    result.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    insideCode = false
                } else {
                    flushParagraph()
                    insideCode = true
                }
                index += 1
                continue
            }
            if insideCode {
                codeLines.append(rawLine)
                index += 1
                continue
            }
            if line.isEmpty {
                flushParagraph()
                index += 1
                continue
            }
            if line.contains("|"), index + 1 < lines.count, Self.isTableSeparator(lines[index + 1]) {
                flushParagraph()
                let headers = Self.tableCells(rawLine)
                var rows: [[String]] = []
                var cursor = index + 2
                while cursor < lines.count {
                    let candidate = lines[cursor]
                    let trimmed = candidate.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || !candidate.contains("|") { break }
                    rows.append(Self.tableCells(candidate))
                    cursor += 1
                }
                result.append(.table(headers: headers, rows: rows))
                index = cursor
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flushParagraph()
                result.append(.bullet(String(line.dropFirst(2))))
            } else if line.hasPrefix("#") {
                flushParagraph()
                result.append(.heading(line.trimmingCharacters(in: CharacterSet(charactersIn: "# "))))
            } else if let match = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                flushParagraph()
                let marker = String(line[line.startIndex..<match.upperBound]).trimmingCharacters(in: .whitespaces)
                result.append(.numbered(marker, String(line[match.upperBound...])))
            } else {
                paragraph.append(line)
            }
            index += 1
        }
        if insideCode { result.append(.code(codeLines.joined(separator: "\n"))) }
        flushParagraph()
        return result
    }

    private static func tableCells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = tableCells(line)
        guard cells.count >= 2 else { return false }
        return cells.allSatisfy { cell in
            cell.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }
}

struct ConversationView: View {
    @Bindable var model: ConnectionModel
    @State private var didAutoSend = false
    @State private var expandedTurns: Set<Int> = []
    @State private var showingCamera = false
    @State private var photoItem: PhotosPickerItem?
    @FocusState private var composerFocused: Bool

    private struct TimelineEntry: Identifiable {
        let id: String
        let sequence: Int
        let message: PocketMessage?
        let group: PocketStepGroup?
    }

    private var entries: [TimelineEntry] {
        var result: [TimelineEntry] = model.messages.map {
            TimelineEntry(id: $0.id, sequence: $0.sequence, message: $0, group: nil)
        }
        for group in model.stepGroups {
            result.append(TimelineEntry(id: "steps-\(group.turn)", sequence: group.sequence, message: nil, group: group))
        }
        return result.sorted { lhs, rhs in
            if lhs.sequence == rhs.sequence { return lhs.message != nil }
            return lhs.sequence < rhs.sequence
        }
    }

    private var canSend: Bool {
        !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.draftImages.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.conversationError {
                Text(error).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.vertical, 8).background(.red.opacity(0.06))
            }
            HStack(spacing: 6) {
                if model.isDemoMode {
                    Image(systemName: "play.circle").font(.caption2).foregroundStyle(.secondary)
                    Text("演示模式 · 示例数据，未连接电脑").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    Circle().fill(model.liveConnectionState == "已连接" ? .green : .orange).frame(width: 7, height: 7)
                    Text("实时连接：\(model.liveConnectionState)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if model.isTurnRunning {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            HStack(spacing: 5) {
                                ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                                Text("深度求索中 · \(elapsed(since: model.turnStartedAt, now: context.date))")
                                    .font(.caption).foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37))
                                Button { Task { await model.cancelTurn() } } label: {
                                    Image(systemName: "stop.circle.fill").font(.caption)
                                        .foregroundStyle(.secondary)
                                }.accessibilityLabel("停止生成")
                            }
                        }
                    }
                }
            }.padding(.horizontal).padding(.vertical, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if model.isLoadingConversation && model.messages.isEmpty && model.steps.isEmpty {
                            ProgressView().padding(.top, 36)
                        }
                        if entries.isEmpty && !model.isLoadingConversation {
                            ContentUnavailableView("开始对话", systemImage: "text.bubble", description: Text("发送第一条消息。"))
                        }
                        ForEach(entries) { entry in
                            if let message = entry.message {
                                MessageRow(message: message, model: model).id(entry.id)
                            } else if let group = entry.group {
                                ProcessRow(group: group, expanded: expandedTurns.contains(group.turn), model: model) {
                                    if expandedTurns.contains(group.turn) { expandedTurns.remove(group.turn) } else { expandedTurns.insert(group.turn) }
                                }.id(entry.id)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded { composerFocused = false })
                .onChange(of: model.messages.count) { oldCount, newCount in
                    timingLog("ui_messages_changed old=\(oldCount) new=\(newCount)")
                    guard oldCount > 0, newCount > oldCount, let id = model.messages.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            Divider()
            inputBar
        }
        .navigationTitle(model.currentConversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { UIPasteboard.general.string = model.diagnosticReport() } label: { Image(systemName: "doc.on.doc") }
                    .accessibilityLabel("复制诊断记录")
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker { image in model.addDraftImage(image) }.ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    model.addDraftImage(image)
                }
                photoItem = nil
            }
        }
        .task {
#if DEBUG
            if !didAutoSend, let text = DebugLaunch.sendText {
                didAutoSend = true
                if let path = DebugLaunch.attachPath {
                    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : documents.appendingPathComponent(path)
                    if let data = try? Data(contentsOf: url), let image = UIImage(data: data) { model.addDraftImage(image) }
                }
                try? await Task.sleep(for: .seconds(2))
                model.draft = text
                model.sendMessage()
            }
#endif
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if !model.draftImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.draftImages) { image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image.uiImage).resizable().scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Button {
                                    model.draftImages.removeAll { $0.id == image.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 16))
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                }
                                .offset(x: 5, y: -5)
                            }
                        }
                    }.padding(.horizontal).padding(.top, 6)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "photo").font(.system(size: 20))
                        .foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37))
                        .frame(width: 38, height: 38)
                }
                .accessibilityLabel("从相册选择图片")
                Button { showingCamera = true } label: {
                    Image(systemName: "camera").font(.system(size: 20))
                        .foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37))
                        .frame(width: 38, height: 38)
                }
                .accessibilityLabel("拍照")
                TextField("发送消息", text: $model.draft, axis: .vertical).lineLimit(1...5)
                    .focused($composerFocused)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                if model.isSending {
                    Button { model.cancelSend() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white).frame(width: 44, height: 44)
                            .background(Color.red.opacity(0.85), in: Circle())
                    }.accessibilityLabel("取消发送")
                } else {
                    Button { model.sendMessage() } label: {
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white).frame(width: 44, height: 44)
                            .background(canSend ? Color(red: 0.08, green: 0.48, blue: 0.37) : .gray, in: Circle())
                    }.disabled(!canSend).accessibilityLabel("发送消息")
                }
            }.padding(.horizontal).padding(.vertical, 10)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(.background)
    }

    private func elapsed(since start: Date?, now: Date) -> String {
        guard let start else { return "计算中" }
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return seconds < 60 ? "\(seconds) 秒" : "\(seconds / 60) 分 \(seconds % 60) 秒"
    }
}

struct MessageRow: View {
    let message: PocketMessage
    @Bindable var model: ConnectionModel

    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 5) {
            HStack(spacing: 5) {
                if !message.isUser {
                    Image(systemName: "sparkle").foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37))
                }
                Text(message.isUser ? "你" : "DSH").foregroundStyle(.secondary)
            }.font(.caption2.weight(.semibold))
            HStack {
                if message.isUser { Spacer(minLength: 40) }
                VStack(alignment: .leading, spacing: 8) {
                    if !message.localImages.isEmpty {
                        ForEach(Array(message.localImages.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 150, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    } else if !message.images.isEmpty {
                        ForEach(message.images) { ref in
                            AttachmentThumbnail(ref: ref, model: model, size: 150)
                        }
                    }
                    if !message.text.isEmpty {
                        MarkdownBody(text: message.text)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .background(message.isUser ? Color(red: 0.08, green: 0.48, blue: 0.37) : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .foregroundStyle(message.isUser ? .white : .primary)
                    }
                }
                if !message.isUser { Spacer(minLength: 24) }
            }
        }.frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }
}

/// 会话里的图片（用户发的 / 工具结果里的），按 attachmentId 读取电脑端附件。
struct AttachmentThumbnail: View {
    let ref: PocketImageRef
    @Bindable var model: ConnectionModel
    var size: CGFloat = 140
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .tertiarySystemFill))
                    ProgressView()
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task { if image == nil { image = await model.loadImage(ref) } }
    }
}

/// 一步或一轮的工具过程，折叠成一行，展开看细节和图片。
struct ProcessRow: View {
    let group: PocketStepGroup
    let expanded: Bool
    @Bindable var model: ConnectionModel
    let toggle: () -> Void

    private var summary: String {
        let labels = Array(Set(group.steps.map(\.label)))
        let joined = labels.prefix(3).joined(separator: "、")
        return "过程 · \(group.steps.count) 步 · \(joined)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(summary).font(.footnote).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(group.steps) { step in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: step.icon).font(.caption).foregroundStyle(.secondary).frame(width: 16)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.label).font(.footnote)
                                    if !step.detail.isEmpty {
                                        Text(step.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    if !step.resultText.isEmpty {
                                        Text(String(step.resultText.prefix(280))).font(.caption2)
                                            .foregroundStyle(.secondary).lineLimit(4)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            ForEach(step.images) { ref in
                                AttachmentThumbnail(ref: ref, model: model, size: 180)
                            }
                        }
                    }
                }
                .padding(.leading, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
