// 连接、会话和发送的状态机。判断尽量留在 DSHKit，这里只编排。

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


@Observable
final class ConnectionModel {
    static let savedServerAddressKey = "dsh-pocket.server-address"
    static let savedEndpointsKey = "dsh-pocket.saved-endpoints"
    static let finishedAwaitingKey = "dsh-pocket.finished-awaiting"
    static let completionAlertKey = "dsh-pocket.completion-alert"
    static let runningSnapshotKey = "dsh-pocket.session-running"
    /// 记住的地址列表（局域网 + 公网各一份），仅用于手动选择，不自动切换。
    var savedEndpoints: [SavedEndpoint] = []
    /// 已完成、等待用户回复的会话（红点）。持久化，打开会话后清除。
    var finishedAwaitingSessionIds: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: ConnectionModel.finishedAwaitingKey) ?? []
    )
    /// 完成提醒总开关（声音 + 通知）。
    var completionAlertsEnabled: Bool = (UserDefaults.standard.object(forKey: ConnectionModel.completionAlertKey) as? Bool) ?? true
    /// App 是否在前台；后台期间的完成只在回前台时提醒。
    var isAppActive = true
    /// 当前屏幕上真正可见的会话（返回列表后会清空；不能用 sessionStore.selected 判断，它不会清）。
    var visibleSessionId: String?
    /// session/list 的 running 状态机，用于识别"运行中 → 已结束"。
    var completionTracker = SessionCompletionTracker(
        previous: (UserDefaults.standard.dictionary(forKey: ConnectionModel.runningSnapshotKey) as? [String: Bool]) ?? [:]
    )

    /// 只同步最近的消息：公网隧道对 WebSocket 单帧大小有限制，长会话全量同步会被拒。
    static let conversationMessageLimit = 30
    /// 连接配置与状态机（spec/12 第三个对象）。
    /// 字段用计算属性转发，约 140 处调用点暂不改；视图收敛留到批次 3。
    let connection = ConnectionState(
        // 地址优先从 UserDefaults 读；重装后沙盒被清，再从 Keychain 兜底恢复，避免每次重装都要重新扫码。
        serverAddress: UserDefaults.standard.string(forKey: savedServerAddressKey)
            ?? ConnectionVault.loadAddress()
            ?? "http://"
    )
    var isDemoMode = false
    /// 会话列表与缓存的唯一真相（spec/12 第五个对象）。调用点走转发。
    let sessionStore = SessionStore()
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

    /// 当前打开的会话。**保留在模型上**（不属于待删的纯转发）：
    /// 它是「正在编辑哪个会话」这一场景的核心句柄，被 messages/steps/draft 等访问器依赖。
    /// 删掉它等于模型不再持有当前会话，属于改行为，超出 spec/17 范围。
    var activeConversation: ConversationState? {
        get { sessionStore.active }
        set { sessionStore.active = newValue }
    }
    /// 当前活动会话的 id。视图用它判断「这份数据是不是我要的那条」，避免进入瞬间渲染上一条。
    var activeSessionId: String? { activeConversation?.sessionId }

    var messages: [PocketMessage] {
        get { activeConversation?.messages ?? [] }
        set { activeConversation?.messages = newValue }
    }
    var steps: [PocketStep] {
        get { activeConversation?.steps ?? [] }
        set { activeConversation?.steps = newValue }
    }
    var turnFailures: [TurnFailureNotice] {
        get { activeConversation?.turnFailures ?? [] }
        set { activeConversation?.turnFailures = newValue }
    }
    var jobs: [PocketJob] {
        get { activeConversation?.jobs ?? [] }
        set { activeConversation?.jobs = newValue }
    }
    /// 还在跑的（running / stopping）。
    var runningJobs: [PocketJob] { jobs.filter(\.isRunning) }
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
    var liveConnection: LiveConnectionState = .idle {
        didSet { noteNetworkEdgeForDiagnostics() }
    }
    /// 进入断开或重连的时刻。用来在诊断行里写「断了多久」。
    var networkDownSince: Date?
    /// 诊断数据由 Diagnostics 持有（见 spec/12 第一批）。这里保留只读转发，避免一次性改所有调用点。
    let diagnostics = Diagnostics()
    /// 任务名单订阅器（服务，不持有业务数据；名单在 ConversationState.jobs）。
    let jobRoster = JobRoster()
    /// 问答卡状态机（spec/12 第六个抽取对象）。
    let questionInbox = QuestionInbox()
    /// 会话列表的只读网络访问（spec/12）。
    let sessionAPI = SessionAPI()
    /// 单条会话操作（spec/12）。
    /// 网络恢复监听：从断网恢复时立刻补发，不等列表轮询或 WS 重连。
    let networkWatcher = NetworkWatcher()
    /// 监听只启动一次。
    var networkWatcherStarted = false
    /// 本轮启动是否已尝试用设备凭证换票，避免 401 循环。
    var authRefreshAttempted = false
    var diagnosticSamples: [DiagnosticSample] { diagnostics.samples }
    var diagnosticVisits: [DiagnosticVisit] { diagnostics.visits }
    var liveConnectionState: String { liveConnection.label }
    var liveDiagnosticHistory: [String] { diagnostics.history }
    var liveTask: Task<Void, Never>? {
        get { activeConversation?.liveTask }
        set { activeConversation?.liveTask = newValue }
    }
    var fallbackTask: Task<Void, Never>? {
        get { activeConversation?.fallbackTask }
        set { activeConversation?.fallbackTask = newValue }
    }
    var sendTask: Task<Void, Never>?
    var pendingSendID: String?
    var pendingSendRpcId: String?
    /// 发送状态（按会话隔离）：已确认（服务端受理、等待处理）/ 失败（可重发）。
    var ackedSendRpcIds: Set<String> {
        get { activeConversation?.ackedRpcIds ?? [] }
        set { activeConversation?.ackedRpcIds = newValue }
    }
    var failedSendRpcIds: Set<String> {
        get { activeConversation?.failedRpcIds ?? [] }
        set { activeConversation?.failedRpcIds = newValue }
    }
    /// 当前会话里、断网暂存等待一并发送的 rpcId。权威记录在发件箱的 heldOffline，这里只供打开中的会话显示。
    var queuedSendRpcIds: Set<String> {
        get { activeConversation?.queuedRpcIds ?? [] }
        set { activeConversation?.queuedRpcIds = newValue }
    }
    /// 已 ACK、等待消息落库的 rpcId（保留本地 pending，避免消息被吞）。
    var acknowledgedSendRpcIds: Set<String> {
        get { activeConversation?.acknowledgedRpcIds ?? [] }
        set { activeConversation?.acknowledgedRpcIds = newValue }
    }
    /// 发件箱唯一真相（spec/12 第四个对象）。调用点仍走下面的转发。
    let outbox = OutboxCoordinator()
    static let outboxDefaultsKey = OutboxCoordinator.defaultsKey
    var outboxEntries: [OutboxEntry] { outbox.entries }
    var outboxLoaded: Bool { outbox.loaded }
    /// 每次切换会话递增；异步请求返回后用它校验，避免旧会话数据写进新会话。
    var conversationToken: UUID {
        get { activeConversation?.conversationToken ?? UUID() }
        set { activeConversation?.conversationToken = newValue }
    }
    /// turn 起止 seq：用于把"生成中排队发送"的用户消息排到该轮回复之后。
    var turnStarts: [Int] {
        get { activeConversation?.turnStarts ?? [] }
        set { activeConversation?.turnStarts = newValue }
    }
    var turnEnds: [Int] {
        get { activeConversation?.turnEnds ?? [] }
        set { activeConversation?.turnEnds = newValue }
    }
    var cancelledDraft = ""
    var cancelledImages: [PocketDraftImage] = []

    /// 带 `?token=` 的 DSH 认证 URL（浏览器复制出来的地址）：直接用 GET 换 cookie，无需密码。
    var pendingLoginToken: String?
    /// 扫码得到的一次性配对 token（免密码登录）。
    var pendingPairToken: String?

    /// 引用一条消息后递增，用于让输入框自动聚焦。
    var focusComposerTick = 0


    /// 输入框上方显示的"正在引用"状态；发送时转成 DSH 原生 Markdown 引用块。
    var pendingQuote: PendingQuote?

    /// APNs device token：登录成功后注册到插件，用于后台完成推送。
    var pushToken: String? = UserDefaults.standard.string(forKey: PushDelegate.tokenDefaultsKey)
    var pushTokenObserver: NSObjectProtocol?

    init() {
        pushTokenObserver = NotificationCenter.default.addObserver(
            forName: .dshPushTokenUpdated, object: nil, queue: .main
        ) { [weak self] note in
            guard let token = note.object as? String else { return }
            Task { @MainActor in
                self?.pushToken = token
                await self?.syncPushRegistration()
            }
        }
#if DEBUG
        if ProcessInfo.processInfo.environment["DSH_RESET"] == "1" {
            // UI 测试用：每次启动清空持久化状态，保证用例可重复。
            for key in ["dsh-pocket.drafts", "dsh-pocket.finished-awaiting", "dsh-pocket.session-running", "dsh-pocket.send-outbox"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
#endif
        loadSavedEndpoints()
#if DEBUG
        if ProcessInfo.processInfo.environment["DSH_STORE_SHOTS"] == "1" {
            UserDefaults.standard.set("timeline", forKey: "dsh-pocket.session-list-mode")
            if ProcessInfo.processInfo.environment["DSH_CONNECT"] == "1" {
                seedStoreShotHome()
            }
        }
#endif
        if connection.pin.isEmpty, let savedPin = PinKeychain.load() { connection.pin = savedPin }
        CompletionNotifier.shared.configure()
        CompletionNotifier.shared.onReply = { [weak self] sessionId, text in
            await self?.sendNotificationReply(sessionId: sessionId, text: text)
        }
        CompletionNotifier.shared.onOpenSession = { [weak self] sessionId in
            Task { @MainActor in await self?.openSessionFromNotification(sessionId: sessionId) }
        }
        if completionAlertsEnabled,
           ProcessInfo.processInfo.environment["DSH_NO_NOTIF_PROMPT"] != "1" {
            CompletionNotifier.shared.requestPermission()
        }
    }

#if DEBUG
#endif

    // MARK: - 地址记忆与自动切换（局域网优先）

    enum MarkdownSegment: Equatable {
        case text(String)
        case image(URL, caption: String?)
    }

    // MARK: - 演示模式（App Store 审核 / 没有电脑时体验）

    /// 演示会话列表。标题走 L10n——英文界面的 App Store 截图不能出现中文标题。
    static var demoSessionList: [PocketSession] {
        let now = Date().timeIntervalSince1970
        return [
            PocketSession(sessionId: "demo-1", updatedAt: now - 60, running: false, blank: false,
                          title: L10n.t("做一个 iOS 版 DSH"), cwd: "~/projects/ios-client"),
            PocketSession(sessionId: "demo-2", updatedAt: now - 3600, running: false, blank: false,
                          title: L10n.t("插件市场里有什么好玩的"), cwd: "~/projects/dsh"),
            PocketSession(sessionId: "demo-3", updatedAt: now - 7200, running: false, blank: false,
                          title: L10n.t("规划东京 5 天行程"), cwd: "~/Documents/trip"),
            PocketSession(sessionId: "demo-4", updatedAt: now - 86400, running: false, blank: false,
                          title: L10n.t("这份体检报告怎么看"), cwd: "~/Documents/health"),
            PocketSession(sessionId: "demo-5", updatedAt: now - 172800, running: false, blank: false,
                          title: L10n.t("把会议记录变成行动项"), cwd: "~/Documents/work")
        ]
    }

    static let demoPicture: UIImage = {
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

    /// 商店截图用的插件设置卡片。程序绘制，不放二维码，也不打进额外图片资源。
    static var storeShotPicture: UIImage {
        let en = LanguageStore.shared.isEnglish
        let size = CGSize(width: 900, height: 900)
        let brand = UIColor(red: 0.08, green: 0.48, blue: 0.37, alpha: 1)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(x: 48, y: 64, width: 804, height: 772), cornerRadius: 36).fill()
            brand.setFill()
            UIBezierPath(roundedRect: CGRect(x: 88, y: 108, width: 84, height: 84), cornerRadius: 20).fill()
            let title = en ? "Phone access" : "手机访问"
            title.draw(at: CGPoint(x: 196, y: 118), withAttributes: [
                .font: UIFont.systemFont(ofSize: 48, weight: .semibold),
                .foregroundColor: UIColor.black
            ])
            (en ? "iOS connector" : "iOS 连接器").draw(at: CGPoint(x: 196, y: 176), withAttributes: [
                .font: UIFont.systemFont(ofSize: 28, weight: .medium),
                .foregroundColor: brand
            ])
            UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 88, y: 236, width: 724, height: 132), cornerRadius: 22).fill()
            (en ? "Fixed address" : "固定地址").draw(at: CGPoint(x: 116, y: 256), withAttributes: [
                .font: UIFont.systemFont(ofSize: 24, weight: .medium),
                .foregroundColor: UIColor.secondaryLabel
            ])
            "studio.example.ts.net".draw(at: CGPoint(x: 116, y: 300), withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 30, weight: .medium),
                .foregroundColor: UIColor.black
            ])
            let note = en
                ? "Pairing code rotates every 60 seconds and works once."
                : "配对码每 60 秒轮换，用一次即失效。"
            note.draw(in: CGRect(x: 88, y: 400, width: 724, height: 150), withAttributes: [
                .font: UIFont.systemFont(ofSize: 34, weight: .regular),
                .foregroundColor: UIColor.darkGray
            ])
            brand.setFill()
            UIBezierPath(roundedRect: CGRect(x: 88, y: 640, width: 724, height: 104), cornerRadius: 26).fill()
            let button = en ? "Copy address" : "复制地址"
            let buttonAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 36, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let buttonSize = button.size(withAttributes: buttonAttr)
            button.draw(at: CGPoint(x: 88 + (724 - buttonSize.width) / 2, y: 668), withAttributes: buttonAttr)
        }
    }

    static var storeShotSessions: [PocketSession] {
        let en = LanguageStore.shared.isEnglish
        let now = Date().timeIntervalSince1970
        let rows: [(String, String, String, TimeInterval)] = en ? [
            ("shot-chat", "Build an iOS client for DSH", "~/projects/ios-client", 180),
            ("shot-media", "Tighten the Phone access card", "~/projects/dsh-pocket-ios", 2400),
            ("shot-3", "What can I reuse from the plugin market", "~/projects/dsh", 7200),
            ("shot-4", "Fix the sent-image thumbnail", "~/projects/ios-client", 20000),
            ("shot-5", "Fill in the missing English strings", "~/projects/ios-client", 40000),
            ("shot-6", "Why did this plugin fail to install", "~/projects/dsh", 80000),
            ("shot-7", "Show a rescan hint when login expires", "~/projects/dsh-pocket-ios", 140000),
            ("shot-8", "Add a badge when a session finishes", "~/projects/ios-client", 200000),
            ("shot-9", "Switch the session list to a timeline", "~/projects/ios-client", 260000)
        ] : [
            ("shot-chat", "做一个 iOS 版 DSH", "~/projects/ios-client", 180),
            ("shot-media", "把手机访问卡片收紧", "~/projects/dsh-pocket-ios", 2400),
            ("shot-3", "插件市场里有什么能复用", "~/projects/dsh", 7200),
            ("shot-4", "修一下发送图片的缩略图", "~/projects/ios-client", 20000),
            ("shot-5", "补齐缺的英文文案", "~/projects/ios-client", 40000),
            ("shot-6", "看看这个插件为什么装失败", "~/projects/dsh", 80000),
            ("shot-7", "登录过期时提示重新扫码", "~/projects/dsh-pocket-ios", 140000),
            ("shot-8", "会话跑完后在列表上标红点", "~/projects/ios-client", 200000),
            ("shot-9", "会话列表改成时间线", "~/projects/ios-client", 260000)
        ]
        return rows.map { id, title, cwd, age in
            PocketSession(sessionId: id, updatedAt: now - age, running: false, blank: false, title: title, cwd: cwd)
        }
    }


    // MARK: - 完成提醒（红点 / 声音 / 通知）

    struct SessionGroup: Identifiable {
        let id: String
        let title: String
        let sessions: [PocketSession]
        let isPinned: Bool
    }

    /// 分组规则：置顶单独成组（最上方），其余按工作区（cwd 目录名）分组；
    /// 组顺序按最近活跃出现顺序。
    var sessionGroups: [SessionGroup] {
        // 分组规则在 DSHKit（可测）；这里只做类型映射与文案。
        let items = sessionStore.sessions.map { SessionGrouping.Item(sessionId: $0.sessionId, cwd: $0.cwd) }
        let byId = Dictionary(sessionStore.sessions.map { ($0.sessionId, $0) }, uniquingKeysWith: { first, _ in first })
        return SessionGrouping.groups(items: items, pinnedIds: sessionStore.pinnedSessionIds).compactMap { group in
            let members = group.sessionIds.compactMap { byId[$0] }
            guard !members.isEmpty else { return nil }
            let title: String
            if group.isPinned {
                title = L10n.t("置顶")
            } else if group.folder == nil {
                title = L10n.t("其他会话")
            } else if group.folder == SessionGrouping.defaultWorkspaceFolder {
                title = L10n.t("默认工作区")
            } else {
                title = group.folder ?? L10n.t("其他会话")
            }
            return SessionGroup(id: group.id, title: title, sessions: members, isPinned: group.isPinned)
        }
    }

    /// 列表展示顺序：置顶在前（最近置顶优先），其余保持服务端顺序。
    var displaySessions: [PocketSession] {
        guard !sessionStore.pinnedSessionIds.isEmpty else { return sessionStore.sessions }
        let byId = Dictionary(sessionStore.sessions.map { ($0.sessionId, $0) }, uniquingKeysWith: { first, _ in first })
        return SessionGrouping.displayOrder(
            items: sessionStore.sessions.map { SessionGrouping.Item(sessionId: $0.sessionId, cwd: $0.cwd) },
            pinnedIds: sessionStore.pinnedSessionIds
        ).compactMap { byId[$0] }
    }

    /// 最近一次被归档的会话（用于列表底部「撤销」）。
    var modelGroups: [ModelGroup] = []
    var selectedModelLabel: String?

    /// 会话地址（用于复制给其他 Agent / 自己记录）。
    var sessionAddress: String {
        guard let session = sessionStore.selected else { return "" }
        return "\(connection.serverAddress)/?session=\(session.sessionId)"
    }

    var lastArchivedSession: PocketSession?

    /// 电脑端该会话的日志文件绝对路径（DSH 的磁盘布局：~/.dsh/sessionStore.sessions/--<cwd转义>--/<sessionId>/session.v4.jsonl.zstd）。
    var sessionLogPath: String? {
        guard let session = sessionStore.selected, let cwd = session.cwd, cwd.hasPrefix("/") else { return nil }
        let trimmed = String(cwd.dropFirst())
        let encoded = "--" + trimmed.replacingOccurrences(of: "/", with: "-") + "--"
        return "\(Self.homeDirectory(for: cwd))/.dsh/sessionStore.sessions/\(encoded)/\(session.sessionId)/session.v4.jsonl.zstd"
    }

    /// 会话页标题：优先用列表中最新标题，避免打开后改标题不刷新。
    var currentConversationTitle: String {
        guard let id = sessionStore.selected?.sessionId else { return "对话" }
        return (sessionStore.sessions.first(where: { $0.sessionId == id }) ?? sessionStore.selected)?.displayTitle ?? "对话"
    }

    // MARK: - 本地发件箱（防止已发送但未落库的消息"消失"）

    /// 按 turn 分组的工具步骤，供会话页折叠成"过程"一行。
    var stepGroups: [PocketStepGroup] {
        // 分组规则在 DSHKit（可测）：轮次变化与「助手文字消息」都是分隔点。
        let source = steps.sorted { $0.sequence < $1.sequence }
        let boundaries = messages
            .filter { !$0.isUser && !$0.isPending && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(\.sequence)
        let groups = StepGrouping.groups(steps: source.map { StepGrouping.Step(turn: $0.turn, sequence: $0.sequence) },
                                         textBoundaries: boundaries)
        return groups.compactMap { indices in
            guard let first = indices.first.map({ source[$0] }) else { return nil }
            return PocketStepGroup(turn: first.turn, sequence: first.sequence,
                                   steps: indices.map { source[$0] })
        }
    }

    /// 用 DSHKit 构建的协议客户端（共享 URLSession cookie）。
    var syncClient: DSHClient? {
        guard let url = try? Self.serverURL(from: connection.serverAddress) else { return nil }
        return DSHClient(baseURL: url)
    }

    /// 唯一 RPC 取用口：协议实现在 DSHKit，这里只按当前地址构造客户端。
    /// 地址无效时抛 `ConnectionError.invalidURL`，与旧实现一致。
    var rpcClient: DSHClient {
        get throws {
            guard let client = syncClient else { throw ConnectionError.invalidURL(connection.serverAddress) }
            return client
        }
    }

}
