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
    /// 当前渲染模式标识（遥测用）。精简已转正，固定为 compact。
    var renderModeLabel: String { "compact" }

    /// 最近一次消息列表重排（`entries`）的耗时与规模。
    ///
    /// `@ObservationIgnored`：这些是纯粹的性能样本，写它不该触发界面刷新，
    /// 否则会形成「统计 → 刷新 → 再统计」的自激循环。
    /// 滚动帧率监控（绘制层指标，与数据层的 renderMs 互补）。
    @ObservationIgnored let frameMonitor = RenderFrameMonitor()
    @ObservationIgnored var lastRenderMs: Double = 0
    @ObservationIgnored var lastRenderEntryCount: Int = 0
    @ObservationIgnored var lastRenderMessageCount: Int = 0
    @ObservationIgnored var lastRenderStepGroupCount: Int = 0

    /// 自动切换连接（局域网优先）。
    ///
    /// **默认开启**（2026-11-21 用户定）：局域网省掉的是 TLS 握手 + 隧道封装这类固定开销，
    /// 比几毫秒的 RTT 差异值钱得多；用户不该为此手动点开关。
    /// 用 `object(forKey:) == nil` 判断「从未设置过」，否则 `bool(forKey:)` 会把未设置读成 false，
    /// 老用户升级后反而拿不到新默认值。
    var autoRouteEnabled: Bool = {
        let key = "dsh-pocket.auto-route"
        if UserDefaults.standard.object(forKey: key) == nil { return true }
        return UserDefaults.standard.bool(forKey: key)
    }() {
        didSet { UserDefaults.standard.set(autoRouteEnabled, forKey: "dsh-pocket.auto-route") }
    }
    /// 当前屏幕上真正可见的会话（返回列表后会清空；不能用 sessionStore.selected 判断，它不会清）。
    var visibleSessionId: String?
    /// session/list 的 running 状态机，用于识别"运行中 → 已结束"。
    var completionTracker = SessionCompletionTracker(
        previous: (UserDefaults.standard.dictionary(forKey: ConnectionModel.runningSnapshotKey) as? [String: Bool]) ?? [:]
    )

    /// 工作区列表（`workspace/follow` 的基线帧）。新建会话时选择、列表分组顺序都用它。
    var workspaces: [PocketWorkspace] = []
    /// 工作区目录的手动顺序（cwd 路径）。拖动排序后立即影响会话列表的分组顺序。
    var workspaceOrder: [String] = []
    /// 上一次调整工作区顺序的失败提示（成功后清空）。
    var lastWorkspaceMoveError: String?
    /// 上一次加载工作区失败的原因（成功时清空）。用于把「为什么空」显示给用户/日志。
    var lastWorkspaceLoadError: String?

    /// 只同步最近的消息：公网隧道对 WebSocket 单帧大小有限制，长会话全量同步会被拒。
    static let conversationMessageLimit = 24
    /// 内存里保留的消息总数硬上限（约 12 轮：用户一句 + 助手一段）。
    ///
    /// 为什么必须硬裁：SwiftUI 的 `LazyVStack` 只延迟**创建**、不回收**已创建**的视图。
    /// 压测实测 400 条消息滚动一遍，内存从 399 MB 涨到 1.4 GB（会被系统 OOM 杀掉）。
    /// 用户明确「历史基本不看」，所以数据层直接裁掉最旧的，不让它进视图树。
    static let retainedMessageLimit = 24
    /// 会话内保留上限（约 15 轮）。
    ///
    /// 为什么需要它：视图层用 VStack（不回收），消息越多内存越高——压测 400 轮
    /// 实测吃到 1682 MB 会被 OOM。List 能回收但**滚不动**（已实测放弃），
    /// 所以只能用「限制条数」来控内存。
    ///
    /// 从 100 → 50 → 30：真机实测约 6.9 MB/条，30 条（约 15 轮）把峰值压到 200 MB 左右，
    /// 同时保留「临时往上翻一两轮」的体验。用户确认这个取舍可接受。
    static let inSessionMessageLimit = 30
    /// 连接配置与状态机（spec/12 第三个对象）。
    /// 字段用计算属性转发，约 140 处调用点暂不改；视图收敛留到批次 3。
    let connection = ConnectionState(
        // 地址优先从 UserDefaults 读；重装后沙盒被清，再从 Keychain 兜底恢复，避免每次重装都要重新扫码。
        serverAddress: ConnectionModel.debugServerOverride
            ?? UserDefaults.standard.string(forKey: savedServerAddressKey)
            ?? ConnectionVault.loadAddress()
            ?? "http://"
    )

    /// DEBUG 自动化：`DSH_DEV_SERVER` 直接顶掉已存地址，`DSH_DEV_AUTOCONNECT=1` 时启动即连。
    ///
    /// 为什么需要：手机端插件面板的端到端验证要先连上电脑，而连接要手输地址和访问密码。
    /// 有了这两个入口，截图和 UI 测试就能全自动，不必人工点一遍。
    /// **只读 DEBUG 环境变量**，正式包这段恒为 nil / false。
    static var debugServerOverride: String? {
#if DEBUG
        let raw = (ProcessInfo.processInfo.environment["DSH_DEV_SERVER"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
#else
        return nil
#endif
    }

    /// DEBUG 下是否要启动即自动连接。
    static var debugAutoConnect: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["DSH_DEV_AUTOCONNECT"] == "1"
#else
        false
#endif
    }

    /// DEBUG 下是否一启动就弹出插件面板（截图/UI 验证用）。
    static var debugOpenPlugins: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["DSH_DEV_OPEN"] == "plugins"
#else
        false
#endif
    }

    /// DEBUG 下自动填的访问密码。
    static var debugPin: String? {
#if DEBUG
        let raw = (ProcessInfo.processInfo.environment["DSH_DEV_PIN"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
#else
        return nil
#endif
    }
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
    /// `$events` 通道的常驻任务（provider 路径）。连上后一直跑，断开自动重连。
    @ObservationIgnored var remoteEventsTask: Task<Void, Never>?
    /// 会话列表的只读网络访问（spec/12）。
    let sessionAPI = SessionAPI()
    /// 单条会话操作（spec/12）。
    /// 网络恢复监听：从断网恢复时立刻补发，不等列表轮询或 WS 重连。
    let networkWatcher = NetworkWatcher()
    /// 连接健康探测（哪条地址能用、多快）。放在模型上而不是视图里，
    /// 是为了让遥测上报也能带上它——否则「不可达」只能靠用户截图。
    ///
    /// 用 `lazy` 而不是 `let x = EndpointProbeRunner()`：后者会在 `ConnectionModel`
    /// 的非隔离初始化上下文里调用 @MainActor 的 init，Swift 6 直接报错。
    @ObservationIgnored
    lazy var probeRunner = EndpointProbeRunner()

    /// 探测结果镜像。放在这里而不是只放在 `probeRunner` 里：
    /// `@ObservationIgnored` 的嵌套对象改动不会触发设置页刷新（实测：遥测有 26ms，
    /// 界面却一直写「检测中」）。由 probeRound 回来时同步一份，UI 直接读它。
    var probeResults: [String: HealthState] = [:]
    /// 每个地址的时延曲线（最近若干次探测）。UI 直接读它画 sparkline。
    var probeLatency: [String: LatencySeries] = [:]
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
        // 一次性迁移：会话列表默认显示方式从「按时间线」改为「按工作区分组」。
        // 光改 @AppStorage 的初始值没用——key 一旦写过（老用户都写过），
        // 初始值就被忽略。用一个独立标记保证只迁移一次，之后用户手动切换不再被覆盖。
        let groupedDefaultKey = "dsh-pocket.session-list-mode.default-grouped.v1"
        if !UserDefaults.standard.bool(forKey: groupedDefaultKey) {
            UserDefaults.standard.set(SessionListMode.grouped.rawValue, forKey: "dsh-pocket.session-list-mode")
            UserDefaults.standard.set(true, forKey: groupedDefaultKey)
        }
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
        // 不在这里请求通知授权：启动时弹系统框会打断用户，且会提前加载 UserNotifications。
        // 授权请求改到「首次真要发通知」（CompletionNotifier.notify）或用户主动开关时。
        DiagFileLog.log("model-init footprint=\(Int(Diagnostics.memoryFootprintMB()))MB")
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
        // 压测：sessions:N 生成 N 个虚构会话，用来测列表规模与分组计算。
        #if DEBUG
        if let scaled = DebugLaunch.stressScenarios.first(where: {
            if case .sessions = $0 { return true }
            return false
        }), case .sessions(let count) = scaled {
            return (0..<count).map { index in
                PocketSession(sessionId: "stress-session-\(index)",
                              updatedAt: now - Double(index * 60),
                              running: false, blank: false,
                              title: "压测会话 \(index + 1)",
                              cwd: index % 7 == 0 ? "~/projects/stress" : "~/projects/other")
            }
        }
        #endif
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
        return SessionGrouping.groups(items: items, pinnedIds: sessionStore.pinnedSessionIds,
                                      directoryOrder: workspaceOrder).compactMap { group in
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
    /// 当前推理强度的人话名（模型没公布强度时为 nil）。只用于展示。
    var selectedReasoningLabel: String?
    /// 智能体运行时按发送键的投递方式（全局偏好，来自 DSH 的 `ui-conversation.busyEnter`）。
    ///
    /// **默认 `.steer` 是刻意保留的**：手机上排队会让消息「看起来卡住」，
    /// 这个体感损失远大于误打断（见 `PromptPolicy.defaultLiveMode` 的注释）。
    /// 用户在电脑端设成排队后，`loadBusyEnterPreference()` 会把它同步过来。
    var busyEnterPreference: PromptMode = PromptPolicy.defaultLiveMode
    /// 是否已经成功读过偏好。避免每次进会话都多发一次 RPC。
    var busyEnterLoaded = false

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
