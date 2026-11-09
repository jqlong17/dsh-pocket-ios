import SwiftUI
import Textual
import DSHKit
import VisionKit
import AVFoundation
import Observation
import PhotosUI
import UIKit
import Photos
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

/// 单个会话独立的展示/发送状态。
/// 切换会话时切换 activeConversation 实例，旧会话数据自然不会出现在新会话里（从结构上隔离）。
@Observable
final class ConversationState {
    let sessionId: String
    /// 该会话自己的输入框草稿（切换会话/退出后恢复）。
    var draft: String = ""
    var draftImages: [PocketDraftImage] = []
    var messages: [PocketMessage] = []
    var steps: [PocketStep] = []
    var isLoadingConversation = false
    var conversationError: String?
    var isTurnRunning = false
    var turnStartedAt: Date?
    var scrollToBottomTick = 0
    var lastLiveFrameAt = Date()
    var liveTask: Task<Void, Never>?
    var fallbackTask: Task<Void, Never>?
    /// 实时流是否在运行：避免"返回会话时 liveTask 已结束但仍非 nil"导致不再重连。
    var isFollowing = false
    var coordinator: SessionSyncCoordinator?
    var coordinatorTask: Task<Void, Never>?
    var coordinatorStarted = false
    /// 历史分页：是否还有更早消息、是否正在加载、加载前的滚动锚点。
    var hasMoreOlder = false
    var isLoadingOlder = false
    /// 打开会话后是否收到过实时 turn/start、turn/end（用于区分历史快照与实时状态）。
    var liveTurnEventsSeen = false
    /// 正在等待回答的问题（ask_user_question）。
    var pendingQuestion: PendingUserQuestion?
    var olderAnchorID: String?
    var olderLoadTick = 0
    var conversationToken = UUID()
    var turnStarts: [Int] = []
    var turnEnds: [Int] = []
    var ackedRpcIds: Set<String> = []
    var failedRpcIds: Set<String> = []
    var steeredRpcIds: Set<String> = []

    init(sessionId: String) {
        self.sessionId = sessionId
        self.draft = DraftStore.draft(for: sessionId)
    }
}

@Observable
final class ConnectionModel {
    private static let savedServerAddressKey = "dsh-pocket.server-address"
    private static let savedEndpointsKey = "dsh-pocket.saved-endpoints"
    /// 记住的地址列表（局域网 + 公网各一份），仅用于手动选择，不自动切换。
    var savedEndpoints: [SavedEndpoint] = []

    /// 只同步最近的消息：公网隧道对 WebSocket 单帧大小有限制，长会话全量同步会被拒。
    private static let conversationMessageLimit = 30
    var serverAddress = UserDefaults.standard.string(forKey: savedServerAddressKey) ?? "http://"
    var pin = ""
    var isConnecting = false
    var errorMessage: String?
    /// 连接失败的原因是"电脑地址已失效"（如 quick tunnel 重建换了域名）→ UI 提示重新扫码。
    var addressNeedsRescan = false
    var isConnected = false
    var isDemoMode = false
    var sessions: [PocketSession] = []
    var archivedSessionIds: Set<String> = []
    var isLoadingSessions = false
    var selectedSession: PocketSession?
    var navigationPath: [PocketSession] = []
    private static var imageCache: [String: UIImage] = [:]
    var isSending = false

    /// 输入框草稿按会话隔离（转发到 activeConversation，并持久化到本地）。
    var draft: String {
        get { activeConversation?.draft ?? "" }
        set {
            activeConversation?.draft = newValue
            if let sessionId = activeConversation?.sessionId {
                DraftStore.save(newValue, for: sessionId)
            }
        }
    }
    var draftImages: [PocketDraftImage] {
        get { activeConversation?.draftImages ?? [] }
        set { activeConversation?.draftImages = newValue }
    }

    // MARK: 会话级状态（按 sessionId 独立存放，切换会话即切换实例）

    private(set) var conversations: [String: ConversationState] = [:]
    private(set) var activeConversation: ConversationState?

    var messages: [PocketMessage] {
        get { activeConversation?.messages ?? [] }
        set { activeConversation?.messages = newValue }
    }
    var steps: [PocketStep] {
        get { activeConversation?.steps ?? [] }
        set { activeConversation?.steps = newValue }
    }
    var isLoadingConversation: Bool {
        get { activeConversation?.isLoadingConversation ?? false }
        set { activeConversation?.isLoadingConversation = newValue }
    }
    var conversationError: String? {
        get { activeConversation?.conversationError }
        set { activeConversation?.conversationError = newValue }
    }
    var isTurnRunning: Bool {
        get { activeConversation?.isTurnRunning ?? false }
        set { activeConversation?.isTurnRunning = newValue }
    }
    var turnStartedAt: Date? {
        get { activeConversation?.turnStartedAt }
        set { activeConversation?.turnStartedAt = newValue }
    }
    var scrollToBottomTick: Int {
        get { activeConversation?.scrollToBottomTick ?? 0 }
        set { activeConversation?.scrollToBottomTick = newValue }
    }
    var lastLiveFrameAt: Date {
        get { activeConversation?.lastLiveFrameAt ?? Date() }
        set { activeConversation?.lastLiveFrameAt = newValue }
    }
    var hasMoreOlder: Bool {
        get { activeConversation?.hasMoreOlder ?? false }
        set { activeConversation?.hasMoreOlder = newValue }
    }
    var isLoadingOlder: Bool {
        get { activeConversation?.isLoadingOlder ?? false }
        set { activeConversation?.isLoadingOlder = newValue }
    }
    var olderAnchorID: String? {
        get { activeConversation?.olderAnchorID }
        set { activeConversation?.olderAnchorID = newValue }
    }
    var olderLoadTick: Int {
        get { activeConversation?.olderLoadTick ?? 0 }
        set { activeConversation?.olderLoadTick = newValue }
    }
    var liveTurnEventsSeen: Bool {
        get { activeConversation?.liveTurnEventsSeen ?? false }
        set { activeConversation?.liveTurnEventsSeen = newValue }
    }
    var pendingQuestion: PendingUserQuestion? {
        get { activeConversation?.pendingQuestion }
        set { activeConversation?.pendingQuestion = newValue }
    }
    /// 实时连接状态机（替代原来的字符串状态）。
    enum LiveConnectionState: Equatable {
        case idle
        case demo
        case connecting
        case connected
        case reconnecting(attempt: Int)
        case disconnected(reason: String?)

        var label: String {
            switch self {
            case .idle: return "未连接"
            case .demo: return "演示模式"
            case .connecting: return "正在连接"
            case .connected: return "已连接"
            case .reconnecting(let attempt): return attempt > 1 ? "重连中（第 \(attempt) 次）" : "正在重连"
            case .disconnected: return "已断开"
            }
        }

        var isConnected: Bool { self == .connected }
        var isDisconnected: Bool { if case .disconnected = self { return true }; return false }
    }

    var liveConnection: LiveConnectionState = .idle
    var liveConnectionState: String { liveConnection.label }
    var liveDiagnosticHistory: [String] = []
    var liveTask: Task<Void, Never>? {
        get { activeConversation?.liveTask }
        set { activeConversation?.liveTask = newValue }
    }
    var fallbackTask: Task<Void, Never>? {
        get { activeConversation?.fallbackTask }
        set { activeConversation?.fallbackTask = newValue }
    }
    var sendTask: Task<Void, Never>?
    private var pendingSendID: String?
    private var pendingSendRpcId: String?
    /// 发送状态（按会话隔离）：已确认（服务端受理、等待处理）/ 失败（可重发）。
    private var ackedSendRpcIds: Set<String> {
        get { activeConversation?.ackedRpcIds ?? [] }
        set { activeConversation?.ackedRpcIds = newValue }
    }
    private var failedSendRpcIds: Set<String> {
        get { activeConversation?.failedRpcIds ?? [] }
        set { activeConversation?.failedRpcIds = newValue }
    }
    private static let outboxDefaultsKey = "dsh-pocket.send-outbox"
    private var outboxEntries: [OutboxEntry] = []
    private var outboxLoaded = false
    /// 每次切换会话递增；异步请求返回后用它校验，避免旧会话数据写进新会话。
    private var conversationToken: UUID {
        get { activeConversation?.conversationToken ?? UUID() }
        set { activeConversation?.conversationToken = newValue }
    }
    /// turn 起止 seq：用于把"生成中排队发送"的用户消息排到该轮回复之后。
    private var turnStarts: [Int] {
        get { activeConversation?.turnStarts ?? [] }
        set { activeConversation?.turnStarts = newValue }
    }
    private var turnEnds: [Int] {
        get { activeConversation?.turnEnds ?? [] }
        set { activeConversation?.turnEnds = newValue }
    }
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
    private func isStaleTunnelError(_ error: Error) -> Bool {
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

    private func applyConnectError(_ error: Error) {
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
    private static func normalizedAddress(_ rawValue: String) -> String {
        DSHURL.normalizedBase(rawValue)?.absoluteString ?? rawValue
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
        DSHURL.webSocketURL(from: base, path: path)
    }

    init() {
        loadSavedEndpoints()
    }

    // MARK: - 地址记忆与自动切换（局域网优先）

    private static func endpointKind(of address: String) -> SavedEndpoint.Kind {
        guard let url = URL(string: address), let host = url.host?.lowercased() else { return .custom }
        if host == "localhost" || host.hasSuffix(".local") { return .lan }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            let a = parts[0], b = parts[1]
            if a == 127 || a == 10 || (a == 192 && b == 168) || (a == 172 && (16...31).contains(b)) {
                return .lan
            }
        }
        if host.contains("trycloudflare.com") || url.scheme == "https" { return .publicNetwork }
        return .custom
    }

    private func loadSavedEndpoints() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedEndpointsKey),
              let list = try? JSONDecoder().decode([SavedEndpoint].self, from: data) else { return }
        savedEndpoints = Self.dedupEndpoints(list)
    }

    /// 去重 + 配额：局域网最多 3 个（可分别命名「公司」「家」），公网 1 个，自定义 1 个。
    /// 公网地址很容易失效，没必要存很多。
    private static func dedupEndpoints(_ list: [SavedEndpoint]) -> [SavedEndpoint] {
        var kept: [SavedEndpoint] = []
        var seenAddresses = Set<String>()
        var lanCount = 0
        var publicCount = 0
        var customCount = 0
        for endpoint in list.sorted(by: { $0.lastUsedAt > $1.lastUsedAt }) {
            guard !seenAddresses.contains(endpoint.address) else { continue }
            switch endpoint.kind {
            case .lan:
                guard lanCount < 3 else { continue }
                lanCount += 1
            case .publicNetwork:
                guard publicCount < 1 else { continue }
                publicCount += 1
            case .custom:
                guard customCount < 1 else { continue }
                customCount += 1
            }
            seenAddresses.insert(endpoint.address)
            kept.append(endpoint)
        }
        return kept
    }

    /// 连接成功后记录地址；同一地址只保留一条（供连接页手动选择）。
    func recordEndpoint(_ address: String) {
        guard let url = try? Self.serverURL(from: address) else { return }
        let normalized = url.absoluteString
        let existingLabel = savedEndpoints.first(where: { $0.address == normalized })?.label
        var list = savedEndpoints.filter { $0.address != normalized }
        list.append(SavedEndpoint(address: normalized,
                                  kind: Self.endpointKind(of: normalized),
                                  lastUsedAt: Date().timeIntervalSince1970,
                                  label: existingLabel))
        savedEndpoints = Self.dedupEndpoints(list)
        if let data = try? JSONEncoder().encode(savedEndpoints) {
            UserDefaults.standard.set(data, forKey: Self.savedEndpointsKey)
        }
    }

    /// 用 session/list 的最新 running 校验一次（只在没有实时 turn 事件时生效）。
    @MainActor
    private func refreshRunningState(for sessionId: String) async {
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

    /// 会话列表的 updatedAt 可能是毫秒或秒，统一成 Date。
    private static func dateFromSessionUpdatedAt(_ value: TimeInterval) -> Date {
        let seconds = value > 10_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }

    /// 给已保存地址设置/清除自定义标签（如「公司」「家」）。
    func renameEndpoint(_ address: String, label: String?) {
        guard let index = savedEndpoints.firstIndex(where: { $0.address == address }) else { return }
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        savedEndpoints[index].label = (trimmed?.isEmpty == false) ? trimmed : nil
        if let data = try? JSONEncoder().encode(savedEndpoints) {
            UserDefaults.standard.set(data, forKey: Self.savedEndpointsKey)
        }
    }

    /// 手动切换到某个已保存地址（失败时回滚，保持原连接）。
    @MainActor
    func switchToEndpoint(_ endpoint: SavedEndpoint) async {
        guard !isDemoMode else { return }
        let previous = serverAddress
        serverAddress = endpoint.address
        errorMessage = nil
        do {
            sessions = try await fetchSessions()
            isConnected = true
            recordEndpoint(endpoint.address)
            recordDiagnostic("切换连接：\(endpoint.kind.label) \(endpoint.address)")
        } catch {
            serverAddress = previous
            applyConnectError(error)
            if isConnected { recordDiagnostic("切换连接失败，已回滚：\(error.localizedDescription)") }
        }
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
            applyConnectError(error)
        }
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
        for conversation in conversations.values {
            conversation.liveTask?.cancel()
            conversation.fallbackTask?.cancel()
            conversation.coordinatorTask?.cancel()
            if let coordinator = conversation.coordinator { Task { await coordinator.stop() } }
        }
        conversations.removeAll()
        activeConversation = nil
        selectedSession = nil
        sessions = []
        archivedSessionIds = []
        liveConnection = .idle
        isConnected = false
    }

    // MARK: - 演示模式（App Store 审核 / 没有电脑时体验）

    private static let demoSessionList: [PocketSession] = [
        PocketSession(sessionId: "demo-1", updatedAt: Date().timeIntervalSince1970 - 60, running: true, blank: false,
                      title: "整理 v1.0.2 发布说明", cwd: "~/projects/dsh-pocket-ios"),
        PocketSession(sessionId: "demo-2", updatedAt: Date().timeIntervalSince1970 - 3600, running: false, blank: false,
                      title: "分析 App Store 截图", cwd: "~/projects/dsh-pocket-ios"),
        PocketSession(sessionId: "demo-3", updatedAt: Date().timeIntervalSince1970 - 7200, running: false, blank: false,
                      title: "对比余额插件差异", cwd: "~/projects/plugin-research"),
        PocketSession(sessionId: "demo-4", updatedAt: Date().timeIntervalSince1970 - 86400, running: false, blank: false,
                      title: "重构 Agent 上下文拼接", cwd: "~/projects/ds-agents"),
        PocketSession(sessionId: "demo-5", updatedAt: Date().timeIntervalSince1970 - 172800, running: false, blank: false,
                      title: "排查 WebSocket 断线", cwd: "~/projects/dsh-pocket-ios")
    ]

    private static let demoPicture: UIImage = {
        if let cover = UIImage(named: "DemoHarnessCover") { return cover }
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
        liveConnection = .demo
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
        conversations.removeAll()
        activeConversation = nil
        sessions = []
        draftImages = []
        liveConnection = .idle
    }

    @MainActor
    private func openDemo(_ session: PocketSession) {
        liveTask?.cancel()
        let conversation = ConversationState(sessionId: session.sessionId)
        conversations[session.sessionId] = conversation
        activeConversation = conversation
        selectedSession = session
        messages = Self.demoMessages(for: session.sessionId)
        steps = Self.demoSteps(for: session.sessionId)
        isTurnRunning = session.running
        turnStartedAt = session.running ? Date().addingTimeInterval(-37) : nil
        isLoadingConversation = false
        conversationError = nil
        hasMoreOlder = false
        draftImages = []
        liveConnection = .demo
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
                PocketMessage(demoText: "帮我把这次发布整理成 Release Notes，顺便标一下风险。", isUser: true, sequence: 1),
                PocketMessage(demoText: """
                ## v1.0.2 发布说明

                本次更新集中在**连接稳定性**与**消息可靠性**，建议所有用户升级。

                ### 亮点

                - 生成中发送改为 **steer**：不再排队，直接引导当前回复
                - 消息顺序回归服务端 `seq`，修复偶发乱序
                - 断线自动重连，状态栏可见「重连中」

                | 模块 | 改动 | 风险 |
                | --- | --- | --- |
                | 实时同步 | 迁移到 DSHKit | 中 |
                | 消息顺序 | 移除 turn 重排 | 低 |
                | 滚动 | followsLatest | 低 |

                ```swift
                let sync = SessionSyncCoordinator(
                    sessionId: id, transport: client)
                ```

                风险中等的「实时同步」迁移已在下面展开。
                """, isUser: false, sequence: 4)
            ]
        case "demo-2":
            return [
                PocketMessage(demoText: "看下这张图，帮我提炼 3 个卖点，再写一句 App Store 副标题。",
                              isUser: true, sequence: 1, localImages: [demoPicture]),
                PocketMessage(demoText: """
                这是 **DeepSeek Harness** 的官网首屏截图，公开预览、开源、插件化。

                ### 三个卖点

                1. **随时可用** — 公开预览，下载即用，无需额外配置
                2. **可组合** — 插件体系把能力扩展到日常开发、写作与研究
                3. **开源本地** — 跑在自己电脑上，数据不离开设备

                ### 副标题候选

                - 「你的 Harness，装进手机里。」
                - 「电脑上的 DSH，走到哪都能用。」
                """, isUser: false, sequence: 2)
            ]
        case "demo-3":
            return [
                PocketMessage(demoText: "这三个余额插件有什么差异？给个对比表。", isUser: true, sequence: 1),
                PocketMessage(demoText: """
                三者都解决「余额可见」，但侧重点不同：

                | 插件 | 展示位置 | 能力 |
                | --- | --- | --- |
                | chenzhexi/dsh-api-usage | 侧边栏常驻 | 余额、今日消费、Token、请求数、24h 柱状图 |
                | cailikelog/account-balance | 输入框读数旁 | 剩余余额 |
                | Witherwithwinter/Whale-Widget | 右下角挂件 | 多平台余额（DeepSeek / OpenRouter / Kimi / GLM） |

                想要**信息密度**选第一个；只想**快速看余额**选第二个；**多平台**选第三个。
                """, isUser: false, sequence: 2)
            ]
        case "demo-4":
            return [
                PocketMessage(demoText: "帮我把 Agent 上下文拼接拆成可测试的模块。", isUser: true, sequence: 1),
                PocketMessage(demoText: """
                改动思路分三步：

                1. **拆**：把 system prompt、workspace 上下文、会话历史拆成独立 builder
                2. **合**：统一在 request 组装时按优先级拼接
                3. **测**：补快照测试，固定输入下的输出

                这样避免上下文重复注入，也方便以后按模型裁剪。
                """, isUser: false, sequence: 2)
            ]
        default:
            return [
                PocketMessage(demoText: "WebSocket 偶尔假死，怎么排查？", isUser: true, sequence: 1),
                PocketMessage(demoText: """
                先确认「假死」的特征：UI 显示已连接，但长时间没有任何增量帧。

                ### 排查顺序

                1. 看是否有心跳/看门狗：生成中 25 秒无帧应主动断开重连
                2. 检查隧道是否被中间设备静默断开：对比 `session/page` 与实时帧
                3. 兜底：轮询最近 30 条消息，确认消息是否已经落库

                最后把「重连中/已断开」状态显式展示给用户，避免误以为在回复。
                """, isUser: false, sequence: 2)
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
            errorMessage = nil
            recordDiagnostic("会话列表刷新：\(sessions.count) 个，隐藏归档 \(archivedSessionIds.count) 个")
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            recordDiagnostic("会话列表刷新失败：\(error.localizedDescription)")
            if isStaleTunnelError(error) {
                applyConnectError(error)
            } else {
                errorMessage = "无法读取会话：\(error.localizedDescription)"
            }
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
        if selectedSession?.sessionId == session.sessionId,
           activeConversation?.coordinatorStarted == true { return }

        // 切到独立会话实例：旧会话的实时流停止，状态留存在 conversations 里，不再写入新会话。
        if let current = activeConversation, current.sessionId != session.sessionId {
            current.liveTask?.cancel()
            current.fallbackTask?.cancel()
            current.coordinatorTask?.cancel()
            if let old = current.coordinator { Task { await old.stop() } }
            current.coordinatorStarted = false
        }
        liveTask?.cancel()
        fallbackTask?.cancel()

        let isNewConversation = conversations[session.sessionId] == nil
        let conversation = conversations[session.sessionId] ?? ConversationState(sessionId: session.sessionId)
        conversations[session.sessionId] = conversation
        activeConversation = conversation
        conversation.conversationToken = UUID()
        conversation.turnStarts.removeAll()
        conversation.turnEnds.removeAll()
        conversation.isLoadingConversation = false
        conversation.conversationError = nil
        // 打开时先用会话列表里的 running 状态（快照窗口可能不包含 turn/start 边界）。
        conversation.isTurnRunning = session.running
        conversation.turnStartedAt = session.running
            ? Self.dateFromSessionUpdatedAt(session.updatedAt)
            : nil
        conversation.hasMoreOlder = false
        conversation.isLoadingOlder = false
        conversation.olderAnchorID = nil
        conversation.liveTurnEventsSeen = false
        if isNewConversation {
            conversation.messages = []
            conversation.steps = []
        }

        selectedSession = session
        liveConnection = .connecting
        // 未确认消息重新挂到该会话（发件箱兜底）；已有 messages 的会话保留历史。
        let outboxPending = restoreOutboxPending(for: session)
        for pending in outboxPending where !conversation.messages.contains(where: { $0.rpcId == pending.rpcId }) {
            conversation.messages.append(pending)
        }
        recordDiagnostic("打开会话：\(session.displayTitle)")
        requestScrollToBottom()
        conversation.isLoadingConversation = true
        if let client = syncClient {
            startCoordinator(for: conversation, session: session, client: client)
            // 列表里的 running 可能滞后：4 秒后（且期间没有实时 turn 事件）再核实一次。
            if session.running {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(4))
                    await self?.refreshRunningState(for: session.sessionId)
                }
            }
#if DEBUG
            if DebugLaunch.loadOlder {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(4))
                    self?.loadOlderMessages()
                }
            }
#endif
        } else {
            // 地址异常时保留旧路径兜底。
            liveTask = Task { await loadConversation(session) }
        }
    }

    @MainActor
    private func loadConversation(_ session: PocketSession) async {
        isLoadingConversation = true
        // 历史上限走 HTTP 分页：公网隧道可能限制 WebSocket 单帧大小，
        // 不能只依赖 follow 的首帧快照。
        fallbackTask?.cancel()
        fallbackTask = Task { await pollLiveFallback(session) }
        let token = conversationToken
        let historyTask = Task { await self.loadHistory(session, token: token) }
        await follow(session)
        _ = await historyTask.value
        if activeConversation?.sessionId == session.sessionId,
           selectedSession?.sessionId == session.sessionId,
           isLoadingConversation {
            isLoadingConversation = false
        }
    }

    /// 实时流不可用（例如公网代理拒绝大帧）时，用 HTTP 分页轮询兜底，保证新消息仍能出现。
    @MainActor
    private func pollLiveFallback(_ session: PocketSession) async {
        while !Task.isCancelled,
              activeConversation?.sessionId == session.sessionId,
              selectedSession?.sessionId == session.sessionId {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { break }
            guard activeConversation?.sessionId == session.sessionId,
                  selectedSession?.sessionId == session.sessionId else { return }
            let stalled = isTurnRunning && Date().timeIntervalSince(lastLiveFrameAt) > 15
            if !liveConnection.isConnected || stalled {
                await loadHistory(session)
            }
        }
    }

    @MainActor
    private func loadHistory(_ session: PocketSession, token: UUID? = nil) async {
        do {
            let address: [String: Any] = ["kind": "session", "sessionId": session.sessionId]
            let page = try await rpc("session/page", args: ["request": ["address": address, "maxMessages": Self.conversationMessageLimit]])
            if let token, token != conversationToken { return }
            guard activeConversation?.sessionId == session.sessionId,
                  selectedSession?.sessionId == session.sessionId else { return }
            let wasEmpty = messages.isEmpty
            let records = page["records"] as? [[String: Any]] ?? []
            let history = records.compactMap(PocketMessage.init(record:))
            mergeMessages(history)
            mergeSteps(from: records)
            isLoadingConversation = false
            if wasEmpty { requestScrollToBottom() }
        } catch {
            if error is CancellationError { return }
            guard selectedSession?.sessionId == session.sessionId, messages.isEmpty else { return }
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            conversationError = "无法读取历史对话：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func mergeMessages(_ incoming: [PocketMessage]) {
        loadOutboxIfNeeded()
        var bySequence = Dictionary(uniqueKeysWithValues: messages.filter { !$0.isPending }.map { ($0.sequence, $0) })
        for message in incoming where !message.isPending { bySequence[message.sequence] = message }
        let incomingUserMessages = incoming.filter(\.isUser)
        let incomingRpcIds = Set(incoming.compactMap(\.rpcId).map { $0.lowercased() })
        confirmOutbox(rpcIds: incomingRpcIds)
        ackedSendRpcIds.subtract(incomingRpcIds)
        failedSendRpcIds.subtract(incomingRpcIds)
        activeConversation?.steeredRpcIds.subtract(incomingRpcIds)
        // 只用 rpcId 精确确认 pending。绝不能按“文本出现在历史里”来判断：
        // 用户发过同样内容的短消息（如“继续”）时，会把刚发出的 pending 误删，表现为消息发不出去。
        let previousMaxConfirmed = messages.filter { !$0.isPending }.map(\.sequence).max() ?? -1
        let latestIncomingUser = incomingUserMessages.max { $0.sequence < $1.sequence }
        let pending = messages.filter { message in
            guard message.isPending else { return false }
            if let rpcId = message.rpcId {
                if incomingRpcIds.contains(rpcId.lowercased()) { return false }
                // 兜底：服务端没回填 rpcId（steer 偶发丢确认），但本次新出现了同文本用户消息。
                if incoming.contains(where: {
                    $0.isUser && !$0.isPending && $0.rpcId == nil
                        && $0.text == message.text && $0.sequence > previousMaxConfirmed
                }) {
                    confirmOutbox(rpcIds: [rpcId])
                    return false
                }
                if failedSendRpcIds.contains(rpcId) { return true }
                // 仍在发件箱（未确认）才保留；历史遗留 pending 丢弃。
                return outboxEntries.contains { $0.id.lowercased() == rpcId.lowercased() }
            }
            // 兼容不回 rpcId 的服务端：仅当“发送之后新出现的最后一条用户消息”文本相同才确认。
            if message.rpcId == nil,
               let latest = latestIncomingUser,
               latest.text == message.text,
               latest.sequence > previousMaxConfirmed {
                return false
            }
            return true
        }
        messages = (Array(bySequence.values) + pending).sorted { $0.sequence < $1.sequence }
        restoreMissingOutboxMessages()
        timingLog("model_update incoming=\(incoming.count) total=\(messages.count)")
    }

    /// 电脑端该会话的日志文件绝对路径（DSH 的磁盘布局：~/.dsh/sessions/--<cwd转义>--/<sessionId>/session.v4.jsonl.zstd）。
    var sessionLogPath: String? {
        guard let session = selectedSession, let cwd = session.cwd, cwd.hasPrefix("/") else { return nil }
        let trimmed = String(cwd.dropFirst())
        let encoded = "--" + trimmed.replacingOccurrences(of: "/", with: "-") + "--"
        return "\(Self.homeDirectory(for: cwd))/.dsh/sessions/\(encoded)/\(session.sessionId)/session.v4.jsonl.zstd"
    }

    private static func homeDirectory(for cwd: String) -> String {
        let parts = cwd.split(separator: "/").map(String.init)
        if parts.count >= 2, parts[0] == "Users" { return "/Users/\(parts[1])" }
        if parts.count >= 2, parts[0] == "home" { return "/home/\(parts[1])" }
        return "~"
    }

    /// 会话页标题：优先用列表中最新标题，避免打开后改标题不刷新。
    var currentConversationTitle: String {
        guard let id = selectedSession?.sessionId else { return "对话" }
        return (sessions.first(where: { $0.sessionId == id }) ?? selectedSession)?.displayTitle ?? "对话"
    }

    /// 消息展示排序键：服务端 seq 即唯一真相。
    /// 曾按 turn 区间把"生成中发送的用户消息"重排到本轮回复之后，但 steer 模式下这些消息
    /// 本身会打断当前轮、seq 就在回复之前；重排反而把用户消息和回复顺序弄反，故移除该启发式。
    func displaySortKey(for message: PocketMessage) -> Int {
        message.sequence
    }

    // MARK: - 本地发件箱（防止已发送但未落库的消息"消失"）

    private func loadOutboxIfNeeded() {
        guard !outboxLoaded else { return }
        outboxLoaded = true
        guard let data = UserDefaults.standard.data(forKey: Self.outboxDefaultsKey),
              let entries = try? JSONDecoder().decode([OutboxEntry].self, from: data) else { return }
        // 10 分钟内未确认视为历史遗留：steer 模式下服务端很快落库，长期 pending 只会造成"发送中"假象。
        let cutoff = Date().timeIntervalSince1970 - 10 * 60
        outboxEntries = entries.filter { $0.createdAt > cutoff }
            .map { OutboxEntry(id: $0.id.lowercased(), sessionId: $0.sessionId,
                               text: $0.text, createdAt: $0.createdAt) }
        persistOutbox()
    }

    private func persistOutbox() {
        if let data = try? JSONEncoder().encode(outboxEntries) {
            UserDefaults.standard.set(data, forKey: Self.outboxDefaultsKey)
        }
    }

    @MainActor
    private func addOutbox(sessionId: String, rpcId: String, text: String) {
        guard !text.isEmpty else { return }
        loadOutboxIfNeeded()
        outboxEntries.append(OutboxEntry(id: rpcId.lowercased(), sessionId: sessionId, text: text,
                                         createdAt: Date().timeIntervalSince1970))
        persistOutbox()
    }

    @MainActor
    private func confirmOutbox(rpcIds: Set<String>) {
        guard !rpcIds.isEmpty else { return }
        let ids = Set(rpcIds.map { $0.lowercased() })
        loadOutboxIfNeeded()
        let before = outboxEntries.count
        outboxEntries.removeAll { ids.contains($0.id.lowercased()) }
        if outboxEntries.count != before { persistOutbox() }
    }

    /// 发件箱里已发出、但列表里没有对应消息的条目：补成 pending 气泡，避免"发了但看不见"。
    @MainActor
    private func restoreMissingOutboxMessages() {
        guard !isDemoMode, let session = selectedSession else { return }
        loadOutboxIfNeeded()
        let representedRpcIds = Set(messages.compactMap(\.rpcId).map { $0.lowercased() })
        let missing = outboxEntries.filter {
            $0.sessionId == session.sessionId && !$0.text.isEmpty && !representedRpcIds.contains($0.id.lowercased())
        }
        guard !missing.isEmpty else { return }
        for entry in missing {
            messages.append(PocketMessage(pendingText: entry.text, rpcId: entry.id))
        }
        messages.sort { $0.sequence < $1.sequence }
        recordDiagnostic("补回未确认消息 \(missing.count) 条")
    }

    @MainActor
    private func removeOutbox(rpcIds: Set<String>) {
        guard !rpcIds.isEmpty else { return }
        loadOutboxIfNeeded()
        let ids = Set(rpcIds.map { $0.lowercased() })
        outboxEntries.removeAll { ids.contains($0.id.lowercased()) }
        persistOutbox()
    }

    private func restoreOutboxPending(for session: PocketSession) -> [PocketMessage] {
        loadOutboxIfNeeded()
        return outboxEntries
            .filter { $0.sessionId == session.sessionId && !$0.text.isEmpty }
            .map { PocketMessage(pendingText: $0.text, rpcId: $0.id) }
    }

    enum PendingSendState { case sending, acked(steered: Bool), failed }

    func pendingSendState(for message: PocketMessage) -> PendingSendState? {
        guard message.isPending, let rpcId = message.rpcId else { return nil }
        if failedSendRpcIds.contains(rpcId) { return .failed }
        if ackedSendRpcIds.contains(rpcId) {
            return .acked(steered: activeConversation?.steeredRpcIds.contains(rpcId) ?? false)
        }
        return .sending
    }

    /// 失败消息重发：从发件箱取回文本，作为新消息重新发送。
    @MainActor
    func retryPendingMessage(_ message: PocketMessage) {
        guard let rpcId = message.rpcId, let session = selectedSession,
              let entry = outboxEntries.first(where: { $0.id == rpcId }) else { return }
        failedSendRpcIds.remove(rpcId)
        ackedSendRpcIds.remove(rpcId)
        messages.removeAll { $0.id == message.id }
        removeOutbox(rpcIds: [rpcId])
        draft = entry.text
        sendMessage(in: session)
    }

    @MainActor
    private func requestScrollToBottom() {
        scrollToBottomTick &+= 1
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
            if !turnStarts.contains(sequence) { turnStarts.append(sequence) }
            isTurnRunning = true
            let time = (event["time"] as? NSNumber)?.doubleValue ?? 0
            turnStartedAt = time > 0 ? Date(timeIntervalSince1970: time / 1000) : Date()
        case "turn/end":
            if !turnEnds.contains(sequence) { turnEnds.append(sequence) }
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
                // await 期间可能已切换会话，返回后必须再校验，否则旧会话消息会串进当前会话。
                guard !Task.isCancelled,
                      activeConversation?.sessionId == session.sessionId,
                      selectedSession?.sessionId == session.sessionId else { return }
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
        defer {
            if activeConversation?.sessionId == session.sessionId {
                activeConversation?.isFollowing = false
            }
        }
        guard let base = URL(string: serverAddress),
              let socketURL = Self.webSocketURL(from: base, path: "api/remote.mux") else {
            recordDiagnostic("实时连接未启动：地址无效 \(serverAddress.debugDescription)")
            return
        }
        activeConversation?.isFollowing = true
        var retryDelay: Duration = .seconds(1)
        var retryCount = 0
        var receivedSnapshot = false
        var usedHistoryFallback = false
        while !Task.isCancelled,
              activeConversation?.sessionId == session.sessionId,
              selectedSession?.sessionId == session.sessionId {
            liveConnection = .connecting
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
                    let frame: URLSessionWebSocketTask.Message
                    if isTurnRunning {
                        // 生成中理应持续有事件；25 秒没有任何帧说明连接假死（常见于公网隧道），主动断开重连。
                        frame = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
                            group.addTask {
                                try await withTaskCancellationHandler {
                                    try await socket.receive()
                                } onCancel: {
                                    socket.cancel(with: .goingAway, reason: nil)
                                }
                            }
                            group.addTask {
                                try await Task.sleep(for: .seconds(25))
                                throw ConnectionError.remote("生成中 25 秒无实时数据，主动重连")
                            }
                            guard let first = try await group.next() else {
                                throw ConnectionError.remote("实时连接无数据")
                            }
                            group.cancelAll()
                            return first
                        }
                    } else {
                        frame = try await withTaskCancellationHandler {
                            try await socket.receive()
                        } onCancel: {
                            socket.cancel(with: .goingAway, reason: nil)
                        }
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
                    liveConnection = .connected
                    if conversationError?.hasPrefix("实时连接") == true { conversationError = nil }
                    retryDelay = .seconds(1)
                    pocketLogger.info("follow item valueType=\(valueType, privacy: .public) keys=\(value.keys.sorted().joined(separator: ","), privacy: .public)")
                    acceptLive(value, sessionId: session.sessionId)
                }
                if !Task.isCancelled { throw ConnectionError.remote("实时连接已结束") }
            } catch {
                socket.cancel(with: .goingAway, reason: nil)
                guard !Task.isCancelled else { break }
                liveConnection = .reconnecting(attempt: retryCount)
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
                conversationError = "实时连接中断，正在重连：\(error.localizedDescription)"
                recordDiagnostic("实时连接中断，\(Int(retryDelay.components.seconds)) 秒后重试：\(error.localizedDescription)")
                pocketLogger.error("follow failed: \(error.localizedDescription, privacy: .public)")
                if !receivedSnapshot && !usedHistoryFallback {
                    usedHistoryFallback = true
                    await loadHistory(session)
                }
                do { try await Task.sleep(for: retryDelay) } catch { break }
                retryDelay = min(retryDelay * 2, .seconds(15))
                retryCount += 1
            }
        }
        if selectedSession?.sessionId == session.sessionId { liveConnection = .disconnected(reason: nil) }
    }

    @MainActor
    private func acceptLive(_ value: [String: Any], sessionId: String) {
        // 结构隔离：只接受"当前激活会话"的帧，旧会话迟到帧直接丢弃。
        guard activeConversation?.sessionId == sessionId,
              selectedSession?.sessionId == sessionId else { return }
        lastLiveFrameAt = Date()
        if value["type"] as? String == "snapshot" {
            let records = value["records"] as? [[String: Any]] ?? []
            let history = records.compactMap(PocketMessage.init(record:))
            mergeMessages(history)
            mergeSteps(from: records)
            recordDiagnostic("收到历史快照：\(history.count) 条消息")
            isLoadingConversation = false
            if messages.isEmpty { requestScrollToBottom() }
        } else if let event = value["event"] as? [String: Any] {
            if let message = PocketMessage(event: event) {
                pocketLogger.info("follow message kind=\(message.kind, privacy: .public) seq=\(message.sequence) chars=\(message.text.count)")
                if let pendingIndex = messages.firstIndex(where: { pending in
                    pending.isPending && pending.isUser && (pending.text == message.text
                        || (pending.rpcId != nil && pending.rpcId == message.rpcId))
                }) {
                    messages.remove(at: pendingIndex)
                }
                if message.isUser, let rpcId = message.rpcId {
                    confirmOutbox(rpcIds: [rpcId])
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

    /// 发送按钮入口：先确认当前打开的就是这个会话，避免消息发到别的 session。
    @MainActor
    func sendMessage(in session: PocketSession) {
        if selectedSession?.sessionId != session.sessionId {
            recordDiagnostic("发送前纠正会话：期望 \(session.displayTitle)")
            selectedSession = session
            open(session)
            return
        }
        sendMessage()
    }

    @MainActor
    func sendMessage() {
        if isSending {
            recordDiagnostic("发送被忽略：上一条仍在发送中")
            return
        }
        if isDemoMode {
            sendTask = Task { await self.sendDemoMessage() }
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = draftImages
        guard (!text.isEmpty || !attachments.isEmpty), selectedSession != nil else {
            recordDiagnostic("发送被忽略：文本为空或未打开会话")
            return
        }
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
        if let rpcId = pendingSendRpcId {
            removeOutbox(rpcIds: [rpcId])
            ackedSendRpcIds.remove(rpcId)
            failedSendRpcIds.remove(rpcId)
        }
        pendingSendID = nil
        pendingSendRpcId = nil
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

    /// 用 DSHKit 构建的协议客户端（共享 URLSession cookie）。
    private var syncClient: DSHClient? {
        guard let url = try? Self.serverURL(from: serverAddress) else { return nil }
        return DSHClient(baseURL: url)
    }

    @MainActor
    private func startCoordinator(for conversation: ConversationState, session: PocketSession, client: DSHClient) {
        conversation.coordinatorTask?.cancel()
        if let old = conversation.coordinator { Task { await old.stop() } }
        let config = SyncConfig(maxMessages: Self.conversationMessageLimit,
                                watchdog: .seconds(25),
                                baseBackoff: .seconds(1),
                                maxBackoff: .seconds(15))
        let coordinator = SessionSyncCoordinator(sessionId: session.sessionId, transport: client, config: config)
        conversation.coordinator = coordinator
        conversation.coordinatorStarted = true
        conversation.isLoadingConversation = true
        let updates = coordinator.updates
        conversation.coordinatorTask = Task { [weak self] in
            for await update in updates {
                if Task.isCancelled { break }
                await self?.applyCoordinatorUpdate(update, conversation: conversation)
            }
        }
        Task { await coordinator.start() }
    }

    /// 请求更早一页历史（滚动到顶部附近时调用）。
    @MainActor
    func loadOlderMessages() {
        guard !isDemoMode, !isLoadingOlder, hasMoreOlder,
              let coordinator = activeConversation?.coordinator,
              let oldest = messages.min(by: { $0.sequence < $1.sequence }) else { return }
        isLoadingOlder = true
        olderAnchorID = oldest.id
        recordDiagnostic("请求更早历史：beforeSeq=\(oldest.sequence)")
        Task { await coordinator.loadOlder() }
    }

    @MainActor
    private func applyCoordinatorUpdate(_ update: SessionUpdate, conversation: ConversationState) async {
        guard activeConversation === conversation else { return }
        switch update {
        case .connection(let state):
            liveConnection = Self.appConnectionState(from: state)
            if case .connected = state { conversationError = nil }
        case .snapshot(let dshMessages, let dshSteps, let hasMore):
            mergeMessages(dshMessages.map(Self.pocketMessage(from:)))
            for step in dshSteps { applyDSHStep(step, historical: true) }
            hasMoreOlder = hasMore
            isLoadingConversation = false
        case .messages(let dshMessages):
            mergeMessages(dshMessages.map(Self.pocketMessage(from:)))
            isLoadingConversation = false
            if isLoadingOlder {
                isLoadingOlder = false
                olderLoadTick += 1
            }
        case .hasMore(let more):
            hasMoreOlder = more
            if isLoadingOlder {
                isLoadingOlder = false
                olderLoadTick += 1
            }
            recordDiagnostic("历史分页：\(more ? "还有更早消息" : "已到最早")")
        case .step(let step):
            applyDSHStep(step)
        case .title(_, let title):
            updateSessionTitle(title)
        case .assistantDelta:
            break
        }
    }

    @MainActor
    private func applyDSHStep(_ step: DSHStepEvent, historical: Bool = false) {
        switch step {
        case .toolCall(let sequence, let turn, let callId, let name, let detail, let arguments):
            if !steps.contains(where: { $0.id == callId }) {
                steps.append(PocketStep(id: callId, sequence: sequence, turn: turn, number: 0,
                                        name: name, detail: detail))
                steps.sort { $0.sequence < $1.sequence }
                recordDiagnostic("过程：\(name)\(detail.isEmpty ? "" : "（\(detail)）")")
            }
            if name == "ask_user_question" {
                pendingQuestion = Self.parsePendingQuestion(callId: callId, arguments: arguments)
            }
        case .toolResult(_, _, let callId, let text, let isError, let images):
            if let index = steps.firstIndex(where: { $0.id == callId }) {
                steps[index].resultText = text
                steps[index].isError = isError
                steps[index].finished = true
                if !images.isEmpty {
                    recordDiagnostic("工具结果包含图片：\(images.count) 张")
                    steps[index].images = images.map {
                        PocketImageRef(attachmentId: $0.attachmentId,
                                       mediaType: $0.mediaType,
                                       width: $0.width,
                                       height: $0.height,
                                       name: $0.name)
                    }
                }
            }
            if pendingQuestion?.callId == callId { pendingQuestion = nil }
        case .turnStart(let sequence, _):
            if !turnStarts.contains(sequence) { turnStarts.append(sequence) }
            isTurnRunning = true
            if turnStartedAt == nil { turnStartedAt = Date() }
            Task { await activeConversation?.coordinator?.setExpectingActivity(true) }
        case .turnEnd(let sequence, _):
            if !turnEnds.contains(sequence) { turnEnds.append(sequence) }
            isTurnRunning = false
            Task { await activeConversation?.coordinator?.setExpectingActivity(false) }
        }
    }

    /// 解析 `ask_user_question` 的 arguments（questions/options）。
    private static func parsePendingQuestion(callId: String, arguments: String) -> PendingUserQuestion? {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawQuestions = object["questions"] as? [[String: Any]] else { return nil }
        let items: [PendingUserQuestion.Item] = rawQuestions.compactMap { raw in
            guard let id = raw["id"] as? String,
                  let question = raw["question"] as? String else { return nil }
            let options: [PendingUserQuestion.Option] = (raw["options"] as? [[String: Any]] ?? []).compactMap { opt in
                guard let label = opt["label"] as? String else { return nil }
                return PendingUserQuestion.Option(label: label, description: opt["description"] as? String)
            }
            return PendingUserQuestion.Item(id: id,
                                            header: raw["header"] as? String,
                                            question: question,
                                            detail: raw["detail"] as? String,
                                            options: options,
                                            multiSelect: raw["multiSelect"] as? Bool ?? false)
        }
        guard !items.isEmpty else { return nil }
        return PendingUserQuestion(callId: callId, questions: items)
    }

    /// 回答 `ask_user_question`（userQuestions/answer）。
    @MainActor
    func answerQuestion(_ request: PendingUserQuestion,
                        selected: [String: Set<String>],
                        custom: [String: String]) {
        guard let session = selectedSession else { return }
        let answers: [[String: Any]] = request.questions.map { item in
            var answer: [String: Any] = [
                "id": item.id,
                "selected": Array(selected[item.id] ?? [])
            ]
            let text = (custom[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { answer["custom"] = text }
            return answer
        }
        let args: [String: Any] = [
            "agentId": session.sessionId,
            "callId": request.callId,
            "answer": ["answers": answers]
        ]
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.rpc("userQuestions/answer", args: args)
                await MainActor.run {
                    if self.pendingQuestion?.callId == request.callId { self.pendingQuestion = nil }
                    self.recordDiagnostic("已回答用户问题：\(request.callId)")
                }
            } catch {
                await MainActor.run {
                    self.conversationError = "回答问题失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private static func pocketMessage(from message: DSHMessage) -> PocketMessage {
        PocketMessage(sequence: message.sequence,
                      kind: message.kind,
                      text: message.text,
                      isUser: message.isUser,
                      rpcId: message.rpcId,
                      images: message.images.map {
                          PocketImageRef(attachmentId: $0.attachmentId,
                                         mediaType: $0.mediaType,
                                         width: $0.width,
                                         height: $0.height,
                                         name: $0.name)
                      })
    }

    private static func appConnectionState(from state: SyncConnectionState) -> LiveConnectionState {
        switch state {
        case .idle: return .idle
        case .connecting: return .connecting
        case .connected: return .connected
        case .reconnecting(let attempt): return .reconnecting(attempt: attempt)
        case .disconnected(let reason): return .disconnected(reason: reason)
        }
    }

    /// 手动重连实时流（状态机断开时 UI 上的"重连"按钮）。
    @MainActor
    func manualReconnect() {
        guard let session = selectedSession, !isDemoMode else { return }
        liveConnection = .connecting
        recordDiagnostic("手动重连实时流")
        if let coordinator = activeConversation?.coordinator {
            Task { await coordinator.reconnect() }
            return
        }
        liveTask?.cancel()
        fallbackTask?.cancel()
        liveTask = Task { await loadConversation(session) }
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
        let requestId = UUID().uuidString.lowercased()
        let pending = PocketMessage(pendingText: text, localImages: attachments.map(\.uiImage), rpcId: requestId)
        let sendStarted = Date()
        timingLog("send_typed chars=\(text.count) images=\(attachments.count)")
        recordDiagnostic("用户点击发送：\(text.count) 字，图片 \(attachments.count) 张")
        messages.append(pending)
        pendingSendID = pending.id
        pendingSendRpcId = requestId
        addOutbox(sessionId: session.sessionId, rpcId: requestId, text: text)
        cancelledDraft = text
        cancelledImages = attachments
        draft = ""
        draftImages = []
        isSending = true
        defer {
            isSending = false
            pendingSendID = nil
            pendingSendRpcId = nil
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
            // 生成中发送用 steer：打断当前轮并把新消息作为引导立即处理；
            // 不再用 queue（queue 会把消息排到本轮之后，形成 inbox 排队）。
            let promptMode = isTurnRunning ? "steer" : "queue"
            recordDiagnostic("发送模式：\(promptMode)（生成中=\(isTurnRunning)）")
            _ = try await rpc("session/prompt", args: ["request": [
                "requestId": requestId,
                "sessionId": session.sessionId,
                "mode": promptMode,
                "content": content,
                "clientTimeZone": TimeZone.current.identifier
            ]])
            timingLog("prompt_ack elapsed_ms=\(Int(Date().timeIntervalSince(sendStarted) * 1000))")
            recordDiagnostic("服务端已确认发送，耗时 \(Int(Date().timeIntervalSince(sendStarted) * 1000)) 毫秒")
            ackedSendRpcIds.insert(requestId)
            if promptMode == "steer" { activeConversation?.steeredRpcIds.insert(requestId) }
            Task { await activeConversation?.coordinator?.setExpectingActivity(true) }
            conversationError = nil
            // 服务端已受理：立刻结束"发送中"状态，恢复发送按钮；若为 steer，服务端会打断当前轮。
            isSending = false
            pendingSendID = nil
            cancelledDraft = ""
            cancelledImages = []
            // 先用服务端真实用户消息替换本地待确认消息，保证"用户消息在上、助手回复在下"的顺序；
            // 否则实时回复先到、轮询提前退出时，待确认消息会带着临时序号排在回复后面。
            await loadHistory(session)
            await pollForReply(session, after: text, afterSequence: lastSequence)
            // 服务端 ACK 了但消息始终没有落库（steer 在部分运行状态下会被丢弃）：
            // 标记失败让用户可重发，而不是永远显示"发送中"。
            if ackedSendRpcIds.contains(requestId) {
                failedSendRpcIds.insert(requestId)
                conversationError = "消息已发出但服务端未确认（可能被丢弃），点消息下方「重新发送」重试。"
                recordDiagnostic("发送未被确认，标记失败：\(requestId)")
            }
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                removeOutbox(rpcIds: [requestId])
                messages.removeAll { $0.id == pending.id }
                return
            }
            // 保留气泡并标记失败，用户可直接重发（不再把文字塞回输入框）。
            failedSendRpcIds.insert(requestId)
            conversationError = "发送失败：\(error.localizedDescription)（点消息气泡下方「重新发送」可重试）"
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

/// 桌面端 `ask_user_question` 正在等待用户选择的问题。
struct PendingUserQuestion: Equatable {
    struct Option: Identifiable, Equatable {
        let label: String
        let description: String?
        var id: String { label }
    }
    struct Item: Identifiable, Equatable {
        let id: String
        let header: String?
        let question: String
        let detail: String?
        let options: [Option]
        let multiSelect: Bool
    }
    let callId: String
    let questions: [Item]
}

/// 按会话保存输入框草稿（退出/切换会话后回来还能接着写）。
enum DraftStore {
    private static let key = "dsh-pocket.drafts"

    private static func loadAll() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    static func draft(for sessionId: String) -> String {
        loadAll()[sessionId] ?? ""
    }

    static func save(_ draft: String, for sessionId: String) {
        var all = loadAll()
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            all.removeValue(forKey: sessionId)
        } else {
            all[sessionId] = draft
            // 控制数量，避免无限增长。
            if all.count > 50 {
                all = Dictionary(all.sorted { $0.key < $1.key }.suffix(50), uniquingKeysWith: { a, _ in a })
            }
        }
        UserDefaults.standard.set(all, forKey: key)
    }
}

/// 记住连接过的地址（局域网/公网），供用户手动切换，避免每次重新扫码。
struct SavedEndpoint: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case lan
        case publicNetwork
        case custom

        var label: String {
            switch self {
            case .lan: return "局域网"
            case .publicNetwork: return "公网"
            case .custom: return "自定义"
            }
        }
    }

    let address: String
    let kind: Kind
    var lastUsedAt: Double
    /// 用户自定义标签，例如「公司」「家」；为空时显示 kind.label。
    var label: String?

    var id: String { address }
    var displayName: String { label ?? kind.label }
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
    /// 发送时客户端生成的 requestId，服务端会回填到 user/message 的 source.rpcId，用来精确对账。
    /// 注意：服务端返回的 rpcId 是**小写 UUID**，客户端统一小写后再比较，避免大小写不一致。
    let rpcId: String?

    init(demoText: String, isUser: Bool, sequence: Int, localImages: [UIImage] = []) {
        self.id = "demo-\(sequence)"
        self.sequence = sequence
        self.kind = isUser ? "user/message" : "assistant/message"
        self.text = demoText
        self.isUser = isUser
        self.isPending = false
        self.images = []
        self.localImages = localImages
        self.rpcId = nil
    }

    init(pendingText: String, localImages: [UIImage] = [], rpcId: String? = nil) {
        self.id = "pending-\(UUID().uuidString)"
        self.sequence = Int.max
        self.kind = "user/message"
        self.text = pendingText
        self.isUser = true
        self.isPending = true
        self.images = []
        self.localImages = localImages
        self.rpcId = RPCId.normalized(rpcId)
    }

    init(sequence: Int, kind: String, text: String, isUser: Bool,
         rpcId: String?, images: [PocketImageRef]) {
        self.id = "event-\(sequence)"
        self.sequence = sequence
        self.kind = kind
        self.text = text
        self.isUser = isUser
        self.isPending = false
        self.images = images
        self.localImages = []
        self.rpcId = RPCId.normalized(rpcId)
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
        let source = (message["source"] as? [String: Any]) ?? (data["source"] as? [String: Any])
        if kind == "user/message" {
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
        self.rpcId = RPCId.normalized(source?["rpcId"] as? String)
    }
}

/// 本地发件箱：消息已发出但服务端还没落成 user/message 事件时，保持可见，避免"消息丢了"的错觉。
struct OutboxEntry: Codable, Identifiable {
    let id: String          // = 发送时生成的 rpcId
    let sessionId: String
    let text: String
    let createdAt: Double
}

/// 一张已落到电脑端附件库的图片引用（会话历史 / 工具结果里的图片）。
struct PocketImageRef: Identifiable, Hashable {
    init(attachmentId: String, mediaType: String? = nil, width: Int? = nil,
         height: Int? = nil, name: String? = nil) {
        self.attachmentId = attachmentId
        self.mediaType = mediaType ?? "image/jpeg"
        self.bytes = 0
        self.width = width ?? 0
        self.height = height ?? 0
        self.name = name
    }

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
    static var loadOlder: Bool { environment["DSH_LOAD_OLDER"] == "1" }
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
            // 回到前台只静默刷新列表，不自动切换网络，避免打断当前会话。
            guard phase == .active, model.isConnected else { return }
            Task { await model.loadSessions(silently: true) }
        }
    }
}

struct ConnectView: View {
    @Bindable var model: ConnectionModel
    @State private var showingScanner = false
    @State private var renamingEndpoint: SavedEndpoint?
    @State private var renameText = ""

    /// 产品使用说明（飞书文档，已设置"获得链接的人可阅读"）。
    private static let usageDocURL = URL(string: "https://my.feishu.cn/docx/XyhpdKD2Uo5y1ZxXFbscTpizntc")!

    private var card: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    private var pageBackground: Color { Color(uiColor: .systemGroupedBackground) }
    private var brand: Color { Color(red: 0.08, green: 0.48, blue: 0.37) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                if !model.savedEndpoints.isEmpty { savedEndpointsCard }
                inputCard
                if let error = model.errorMessage { errorBanner(error) }
                connectButton
                demoButton
                Text("演示模式使用内置示例数据，不会连接或发送任何内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(pageBackground.ignoresSafeArea())
        .sheet(isPresented: $showingScanner) {
            NavigationStack {
                QRScannerView { value in if model.useScannedAddress(value) { showingScanner = false } }
                    .navigationTitle("扫描二维码")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showingScanner = false } } }
            }
        }
        .onAppear { model.errorMessage = nil }
        .onChange(of: model.serverAddress) { _, _ in model.errorMessage = nil }
        .alert("命名连接地址", isPresented: Binding(
            get: { renamingEndpoint != nil },
            set: { if !$0 { renamingEndpoint = nil } }
        )) {
            TextField("例如：公司 / 家", text: $renameText)
            Button("保存") {
                if let endpoint = renamingEndpoint {
                    model.renameEndpoint(endpoint.address, label: renameText)
                }
                renamingEndpoint = nil
            }
            Button("清除", role: .destructive) {
                if let endpoint = renamingEndpoint {
                    model.renameEndpoint(endpoint.address, label: nil)
                }
                renamingEndpoint = nil
            }
            Button("取消", role: .cancel) { renamingEndpoint = nil }
        } message: {
            Text("给这个地址起一个有辨识度的名字，例如「公司」或「家」。")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(brand)
                .frame(width: 38, height: 38)
                .background(brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("连接你的 DSH").font(.headline)
                Text("输入电脑地址和访问密码").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Link(destination: Self.usageDocURL) {
                HStack(spacing: 4) {
                    Image(systemName: "book").font(.caption)
                    Text("使用说明").font(.footnote.weight(.medium))
                }
                .foregroundStyle(brand)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("打开 DSH Pocket iOS 使用说明")
        }
        .padding(14)
        .background(card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var savedEndpointsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("已保存的连接")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("点按切换")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            ForEach(Array(model.savedEndpoints.enumerated()), id: \.element.id) { index, endpoint in
                if index > 0 {
                    Divider().padding(.leading, 52)
                }
                Button {
                    model.serverAddress = endpoint.address
                    model.errorMessage = nil
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: endpoint.kind == .lan ? "wifi" : "globe")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(brand)
                            .frame(width: 26, height: 26)
                            .background(brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                if endpoint.label != nil {
                                    Text(endpoint.displayName)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(endpoint.kind.label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(endpoint.kind.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(endpoint.address)
                                .font(.footnote)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Button {
                            renamingEndpoint = endpoint
                            renameText = endpoint.label ?? ""
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("重命名\(endpoint.kind.label)地址")
                        if model.serverAddress == endpoint.address {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(brand)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text("局域网最多保留 3 个（可命名为「公司」「家」），公网保留最近 1 个；公网地址变化后重新扫码更新。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 12)
        }
        .background(card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var inputCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("http://192.168.1.10:3081", text: $model.serverAddress)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.URL)
                    .font(.subheadline)
                Button { showingScanner = true } label: {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(brand)
                        .frame(width: 34, height: 34)
                        .background(brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("扫描 Pocket 二维码")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().padding(.leading, 14)

            SecureField("访问密码", text: $model.pin)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .background(card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func errorBanner(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            if model.addressNeedsRescan {
                Button { showingScanner = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "qrcode.viewfinder")
                        Text("重新扫码连接")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(brand)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var connectButton: some View {
        Button {
            Task { await model.connect() }
        } label: {
            HStack(spacing: 6) {
                if model.isConnecting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                }
                Text(model.isConnecting ? "正在连接" : "连接")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(.white)
            .background(brand, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(model.isConnecting)
        .opacity(model.isConnecting ? 0.7 : 1)
    }

    private var demoButton: some View {
        Button { model.startDemoMode() } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.circle")
                Text("体验演示模式")
            }
            .fontWeight(.medium)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(brand)
            .background(card, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityHint("没有电脑时查看内置示例会话与对话")
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
                Section {
                    Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
                    if model.addressNeedsRescan {
                        Button("重新选择连接地址") { model.disconnect() }
                    }
                }
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !model.savedEndpoints.isEmpty {
                    Menu {
                        ForEach(model.savedEndpoints) { endpoint in
                            Button {
                                Task { await model.switchToEndpoint(endpoint) }
                            } label: {
                                Label("\(endpoint.displayName)：\(endpoint.address)",
                                      systemImage: model.serverAddress == endpoint.address ? "checkmark" : "network")
                            }
                        }
                    } label: {
                        Image(systemName: "network")
                    }
                    .accessibilityLabel("切换连接")
                }
                Button { Task { await model.createSession() } } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("新建会话")
            }
        }
        .navigationTitle("会话")
        .navigationDestination(for: PocketSession.self) { session in
            ConversationView(model: model, session: session)
                // onAppear 在部分 iOS 版本上不会对同一目的地类型重复触发，
                // 用 task(id:) 确保进入/切换会话时一定重新打开对应会话。
                .task(id: session.sessionId) { model.open(session) }
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

/// 聊天气泡里的标题：比默认更克制（默认 H1/H2 太大）。
struct ChatHeadingStyle: StructuredText.HeadingStyle {
    // 以 Textual 基准字号 17pt（iOS .body）计算：
    // H1 20 / H2 18 / H3 17 / H4 16 / H5 15 / H6 13。移动端更克制，标题不抢正文。
    private static let fontScales: [CGFloat] = [1.18, 1.06, 1.0, 0.94, 0.88, 0.76]

    func makeBody(configuration: Configuration) -> some View {
        let index = min(max(configuration.headingLevel - 1, 0), Self.fontScales.count - 1)
        configuration.label
            .textual.fontScale(Self.fontScales[index])
            .fontWeight(.semibold)
            .textual.blockSpacing(.fontScaled(top: 0.9, bottom: 0.35))
    }
}

/// 消息 Markdown 渲染：交给 Textual（MarkdownUI 作者的新库，原生支持跨视图文本选择）。
struct MarkdownBody: View {
    let text: String
    var foreground: Color = .primary

    var body: some View {
        StructuredText(markdown: text)
            .textual.textSelection(.enabled)
            .textual.structuredTextStyle(.gitHub)
            .textual.headingStyle(ChatHeadingStyle())
            .foregroundStyle(foreground)
    }
}

private struct ConversationHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct ConversationView: View {
    @Bindable var model: ConnectionModel
    let session: PocketSession
    @State private var isSettlingScroll = false
    /// 是否停在底部（followsLatest）：在底部才自动跟随新消息，否则只累计未读。
    @State private var isAtBottom = true
    @State private var unreadWhileScrolled = 0
    /// 是否仍"跟随最新"：用户主动上滑后置 false；回到底部/点箭头后置 true。
    @State private var followsLatest = true
    /// 用户上滑时递增，用于让待执行的补滚任务失效。
    @State private var scrollGeneration = 0
    @State private var didAutoSend = false
    @State private var expandedTurns: Set<Int> = []
    /// 分页加载冷却，避免滚动到顶部时连续翻页。
    @State private var olderCooldownUntil = Date.distantPast
    @State private var showingCamera = false
    @State private var photoItem: PhotosPickerItem?
    @FocusState private var composerFocused: Bool
    @State private var copiedLogPath: String?

    private struct TimelineEntry: Identifiable {
        let id: String
        let sortKey: Int      // 展示排序键（排队消息会被推迟到 turn 结束之后）
        let sequence: Int     // 原始 seq，二级排序保证同一 turn 内排队消息的先后顺序
        let message: PocketMessage?
        let group: PocketStepGroup?
    }

    private var entries: [TimelineEntry] {
        var result: [TimelineEntry] = model.messages.map {
            TimelineEntry(id: $0.id, sortKey: model.displaySortKey(for: $0), sequence: $0.sequence, message: $0, group: nil)
        }
        for group in model.stepGroups {
            result.append(TimelineEntry(id: "steps-\(group.turn)", sortKey: group.sequence, sequence: group.sequence, message: nil, group: group))
        }
        return result.sorted { lhs, rhs in
            if lhs.sortKey != rhs.sortKey { return lhs.sortKey < rhs.sortKey }
            // 同一排序键（同一 turn 内排队的多条消息）用原始 seq 保持发送先后。
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            switch (lhs.message, rhs.message) {
            case let (.some(l), .some(r)):
                if l.isPending != r.isPending { return !l.isPending }
                return l.id < r.id
            case (.some, nil):
                return true
            case (nil, .some), (nil, nil):
                return lhs.id < rhs.id
            }
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
                    Circle().fill(Self.liveStateColor(model.liveConnection)).frame(width: 7, height: 7)
                    Text("实时连接：\(model.liveConnection.label)").font(.caption).foregroundStyle(.secondary)
                    if model.liveConnection.isDisconnected {
                        Button("重连") { model.manualReconnect() }
                            .font(.caption2.weight(.semibold))
                    }
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
                    // 用 VStack 而非 LazyVStack：MarkdownUI/图片/表格行高度动态变化，
                    // LazyVStack 会缓存旧高度导致行重叠；会话窗口只有 30 条消息，直接布局代价可忽略。
                    VStack(spacing: 14) {
                        if model.isLoadingOlder {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text("加载更早消息…").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                        }
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
                        // 底部锚点：滚动到它比"最后一条消息"更可靠（能带上后面的过程行/占位）。
                        Color.clear.frame(height: 1).id(Self.bottomAnchorID)
                    }
                    .padding()
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: ConversationHeightKey.self, value: geo.size.height)
                        }
                    )
                }
                .onPreferenceChange(ConversationHeightKey.self) { _ in
                    // 行高异步变化（Textual 表格/图片晚渲染）会让内容变高；只要仍在跟随最新，
                    // 就补一次贴底，避免"最后一条消息下方留出空白"。
                    guard isSettlingScroll || followsLatest else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                    }
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded { composerFocused = false })
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            if value.translation.height > 10 { followsLatest = false }
                        }
                )
                // 视图刚出现时先补滚一次（打开会话的 tick 可能早于 onChange 订阅）。
                .onAppear {
                    isSettlingScroll = true
                    scrollToBottom(proxy: proxy)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { isSettlingScroll = false }
                }
                // 打开会话、历史/快照到达：模型递增 tick，视图统一滚到底部。
                .onChange(of: model.scrollToBottomTick) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: model.messages.count) { oldCount, newCount in
                    timingLog("ui_messages_changed old=\(oldCount) new=\(newCount)")
                    guard newCount != oldCount else { return }
                    if isAtBottom || isSettlingScroll {
                        scrollToBottom(proxy: proxy)
                    } else if newCount > oldCount {
                        unreadWhileScrolled += newCount - oldCount
                    }
                }
                .onChange(of: model.steps.count) { oldCount, newCount in
                    guard newCount != oldCount else { return }
                    if isAtBottom || isSettlingScroll { scrollToBottom(proxy: proxy) }
                }
                .onChange(of: model.olderLoadTick) { _, _ in
                    olderCooldownUntil = Date().addingTimeInterval(1.5)
                    guard let anchor = model.olderAnchorID else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo(anchor, anchor: .top)
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, topOffset in
                    guard topOffset < 80,
                          model.hasMoreOlder,
                          !model.isLoadingOlder,
                          !model.messages.isEmpty,
                          Date() >= olderCooldownUntil else { return }
                    olderCooldownUntil = Date().addingTimeInterval(1.5)
                    model.loadOlderMessages()
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    let distance = geometry.contentSize.height - geometry.containerSize.height - geometry.contentOffset.y
                    return distance <= 48
                } action: { _, atBottom in
                    if atBottom {
                        isAtBottom = true
                        unreadWhileScrolled = 0
                        followsLatest = true
                    } else if !followsLatest {
                        // 已在跟随状态下被程序化贴底时，几何短暂变化不打断跟随；只有用户上滑才停。
                        isAtBottom = false
                    } else {
                        scrollGeneration &+= 1
                        isAtBottom = false
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !isAtBottom, !entries.isEmpty {
                        Button {
                            unreadWhileScrolled = 0
                            isAtBottom = true
                            followsLatest = true
                            scrollToBottom(proxy: proxy, force: true)
                        } label: {
                            HStack(spacing: 5) {
                                if unreadWhileScrolled > 0 {
                                    Text("\(unreadWhileScrolled)")
                                        .monospacedDigit()
                                        .font(.caption2.weight(.bold))
                                }
                                Image(systemName: "arrow.down")
                                    .font(.footnote.weight(.semibold))
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(unreadWhileScrolled > 0 ? "\(unreadWhileScrolled) 条未读，滚到底部" : "滚到底部")
                        .accessibilityIdentifier("back-to-bottom")
                        .padding(.trailing, 16)
                        .padding(.bottom, 12)
                    }
                }
            }
            if let question = model.pendingQuestion {
                UserQuestionCard(request: question, model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider()
            inputBar
        }
        .navigationTitle(model.currentConversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let path = model.sessionLogPath {
                        UIPasteboard.general.string = path
                        copiedLogPath = path
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("复制会话日志路径")
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = model.diagnosticReport()
                    } label: {
                        Label("复制诊断信息", systemImage: "stethoscope")
                    }
                }
            }
        }
        .alert("已复制会话日志路径", isPresented: Binding(
            get: { copiedLogPath != nil },
            set: { if !$0 { copiedLogPath = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(copiedLogPath ?? "")
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
                    .accessibilityIdentifier("composer-field")
                if model.isSending {
                    Button { model.cancelSend() } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white).frame(width: 44, height: 44)
                            .background(Color.red.opacity(0.85), in: Circle())
                    }.accessibilityLabel("取消发送").accessibilityIdentifier("cancel-send")
                } else {
                    Button { model.sendMessage(in: session) } label: {
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white).frame(width: 44, height: 44)
                            .background(canSend ? Color(red: 0.08, green: 0.48, blue: 0.37) : .gray, in: Circle())
                    }.disabled(!canSend).accessibilityLabel("发送消息").accessibilityIdentifier("send-button")
                }
            }.padding(.horizontal).padding(.vertical, 10)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(.background)
    }

    private static let bottomAnchorID = "conversation-bottom-anchor"

    private static func liveStateColor(_ state: ConnectionModel.LiveConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected: return .red
        case .idle, .demo: return .gray
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, force: Bool = false) {
        // followsLatest：用户主动往上翻时不要抢滚动；只有点击"回到底部"才强制。
        if !force && !isAtBottom && !isSettlingScroll { return }
        let generation = scrollGeneration
        // 点"回到底部"只补滚两帧：用户随后立刻上滑，必须立即失效（不能强制抢回底部）。
        let delays: [Double]
        if force {
            delays = [0, 0.15]
        } else if isSettlingScroll {
            delays = [0, 0.1, 0.3, 0.7, 1.2, 2.0]
        } else {
            delays = [0]
        }
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // 用户已上滑（generation 递增）或会话已切换：放弃这次补滚。
                guard generation == scrollGeneration else { return }
                guard force || isSettlingScroll || isAtBottom else { return }
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        }
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
    @State private var previewItem: PreviewImageItem?

    private func pendingStateColor(_ state: ConnectionModel.PendingSendState) -> Color {
        if case .failed = state { return Color.red.opacity(0.85) }
        return Color.secondary
    }

    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 5) {
            HStack(spacing: 5) {
                if !message.isUser {
                    Image(systemName: "sparkle").foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37))
                }
                Text(message.isUser ? "你" : "DSH").foregroundStyle(.secondary)
                if !message.text.isEmpty {
                    Button {
                        UIPasteboard.general.string = message.text
                    } label: {
                        Image(systemName: "doc.on.doc").font(.caption2).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("复制整条消息")
                }
            }.font(.caption2.weight(.semibold))
            HStack {
                if message.isUser { Spacer(minLength: 40) }
                VStack(alignment: .leading, spacing: 8) {
                    if !message.localImages.isEmpty {
                        ForEach(Array(message.localImages.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 150, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .contentShape(Rectangle())
                                .onTapGesture { previewItem = PreviewImageItem(image: image) }
                        }
                    } else if !message.images.isEmpty {
                        ForEach(message.images) { ref in
                            AttachmentThumbnail(ref: ref, model: model, size: 150)
                        }
                    }
                    if !message.text.isEmpty {
                        MarkdownBody(text: message.text, foreground: message.isUser ? .white : .primary)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .background(message.isUser ? Color(red: 0.08, green: 0.48, blue: 0.37) : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .foregroundStyle(message.isUser ? .white : .primary)
                    }
                }
                if !message.isUser { Spacer(minLength: 24) }
            }
            if message.isPending, let state = model.pendingSendState(for: message) {
                HStack(spacing: 5) {
                    switch state {
                    case .sending:
                        ProgressView().scaleEffect(0.55).frame(width: 11, height: 11)
                        Text("发送中…")
                    case .acked(let steered):
                        Image(systemName: steered ? "arrow.triangle.branch" : "clock").font(.caption2)
                        Text(steered ? "已引导，正在继续" : "已发出，等待处理")
                    case .failed:
                        Image(systemName: "exclamationmark.circle").font(.caption2)
                        Text("发送失败")
                        Button("重新发送") { model.retryPendingMessage(message) }
                            .buttonStyle(.borderless)
                            .font(.caption2.weight(.semibold))
                    }
                }
                .font(.caption2)
                .foregroundStyle(pendingStateColor(state))
                .padding(.horizontal, 4)
            }
        }.frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
        .fullScreenCover(item: $previewItem) { item in
            FullscreenImageViewer(image: item.image)
        }
    }
}

struct PreviewImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// 会话里的图片（用户发的 / 工具结果里的），按 attachmentId 读取电脑端附件。
struct AttachmentThumbnail: View {
    let ref: PocketImageRef
    @Bindable var model: ConnectionModel
    var size: CGFloat = 140
    @State private var image: UIImage?
    @State private var showsPreview = false

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
        .contentShape(Rectangle())
        .onTapGesture { if image != nil { showsPreview = true } }
        .fullScreenCover(isPresented: $showsPreview) {
            if let image { FullscreenImageViewer(image: image) }
        }
        .task { if image == nil { image = await model.loadImage(ref) } }
    }
}

/// 全屏图片查看：捏合/双击缩放、关闭、保存到相册、系统分享。
struct FullscreenImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var toast: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in scale = min(max(lastScale * value, 1), 5) }
                        .onEnded { _ in lastScale = scale }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scale = scale > 1 ? 1 : 2.5
                        lastScale = scale
                    }
                }
        }
        .overlay(alignment: .top) {
            HStack(spacing: 12) {
                Button { dismiss() } label: { circleIcon("xmark") }
                    .accessibilityLabel("关闭")
                Spacer()
                ShareLink(item: Image(uiImage: image),
                          preview: SharePreview("图片", image: Image(uiImage: image))) {
                    circleIcon("square.and.arrow.up")
                }
                Button { saveToAlbum() } label: { circleIcon("square.and.arrow.down") }
                    .accessibilityLabel("保存到相册")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toast)
        .statusBarHidden(true)
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(.black.opacity(0.45), in: Circle())
    }

    private func saveToAlbum() {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                toast = success ? "已保存到相册" : "保存失败：\(error?.localizedDescription ?? "未知错误")"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { toast = nil }
            }
        }
    }
}

/// 一步或一轮的工具过程，折叠成一行，展开看细节和图片。
/// 电脑端 `ask_user_question` 等待选择时显示的问题卡片。
struct UserQuestionCard: View {
    let request: PendingUserQuestion
    @Bindable var model: ConnectionModel
    @State private var selected: [String: Set<String>] = [:]
    @State private var custom: [String: String] = [:]

    private var complete: Bool {
        request.questions.allSatisfy { question in
            if !(selected[question.id]?.isEmpty ?? true) { return true }
            return !(custom[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill").foregroundStyle(.orange)
                Text("需要你确认").font(.footnote.weight(.semibold))
                Spacer()
                Text("来自电脑端 DSH").font(.caption2).foregroundStyle(.secondary)
            }

            ForEach(request.questions) { question in
                VStack(alignment: .leading, spacing: 6) {
                    if let header = question.header, !header.isEmpty {
                        Text(header).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(question.question).font(.subheadline.weight(.medium))
                    if let detail = question.detail, !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(question.options) { option in
                        Button { toggle(question, option) } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: isSelected(question, option) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected(question, option) ? Color.green : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label).font(.footnote)
                                    if let description = option.description, !description.isEmpty {
                                        Text(description).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(8)
                            .background(isSelected(question, option) ? Color.green.opacity(0.08) : Color(uiColor: .tertiarySystemBackground),
                                        in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    TextField("其他答案（可选）", text: Binding(
                        get: { custom[question.id] ?? "" },
                        set: { custom[question.id] = $0 }
                    ))
                    .font(.footnote)
                    .textFieldStyle(.roundedBorder)
                }
            }

            Button {
                model.answerQuestion(request, selected: selected, custom: custom)
            } label: {
                Text("提交回答")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .foregroundStyle(.white)
                    .background(Color(red: 0.08, green: 0.48, blue: 0.37).opacity(complete ? 1 : 0.35),
                                in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(!complete)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func isSelected(_ question: PendingUserQuestion.Item, _ option: PendingUserQuestion.Option) -> Bool {
        selected[question.id]?.contains(option.label) ?? false
    }

    private func toggle(_ question: PendingUserQuestion.Item, _ option: PendingUserQuestion.Option) {
        var set = selected[question.id] ?? []
        if question.multiSelect {
            if set.contains(option.label) { set.remove(option.label) } else { set.insert(option.label) }
        } else {
            set = [option.label]
            custom[question.id] = ""
        }
        selected[question.id] = set
    }
}

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
