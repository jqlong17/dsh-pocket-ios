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
import UserNotifications


// MARK: - 应用内语言（简体中文 / English）

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, zh, en
    var id: String { rawValue }
    func title() -> String {
        switch self {
        case .system: return L10n.t("跟随系统")
        case .zh: return "中文"
        case .en: return "English"
        }
    }
}

@Observable
final class LanguageStore {
    static let shared = LanguageStore()
    private static let key = "dsh-pocket.language"
    var code: AppLanguage {
        didSet {
            UserDefaults.standard.set(code.rawValue, forKey: Self.key)
            NotificationCenter.default.post(name: .appLanguageChanged, object: nil)
        }
    }
    init() {
        let saved = UserDefaults.standard.string(forKey: Self.key) ?? AppLanguage.system.rawValue
        code = AppLanguage(rawValue: saved) ?? .system
    }
    var isEnglish: Bool {
        switch code {
        case .en: return true
        case .zh: return false
        case .system:
            let lang = Locale.preferredLanguages.first ?? "zh"
            return !lang.lowercased().hasPrefix("zh")
        }
    }
}

extension Notification.Name { static let appLanguageChanged = Notification.Name("dsh-pocket.language-changed") }

/// 轻量文案表：key 为中文原文，按语言返回对应文案；未收录的文案保持中文。
enum L10n {
    static func t(_ zh: String) -> String {
        LanguageStore.shared.isEnglish ? (en[zh] ?? zh) : zh
    }
    static func tf(_ format: String, _ args: CVarArg...) -> String {
        String(format: t(format), arguments: args)
    }
    static let en: [String: String] = [
        "连接你的 DSH": "Connect to your DSH",
        "输入电脑地址和访问密码": "Enter your computer address and access PIN",
        "使用说明": "How to use",
        "已保存的连接": "Saved connections",
        "点按切换": "Tap to switch",
        "局域网最多保留 3 个（可命名为「公司」「家」），公网保留最近 1 个；公网地址变化后重新扫码更新。": "Up to 3 LAN addresses (name them Office/Home) and the latest 1 public address. Rescan if the public address changes.",
        "连接": "Connect",
        "体验演示模式": "Try demo mode",
        "演示模式使用内置示例数据，不会连接或发送任何内容。": "Demo mode uses sample data. It never connects or sends anything.",
        "会话": "Sessions",
        "演示模式": "Demo mode",
        "示例数据，未连接电脑": "Sample data · not connected",
        "退出": "Exit",
        "设置": "Settings",
        "语言": "Language",
        "跟随系统": "Follow system",
        "中文": "简体中文",
        "完成提醒": "Completion alerts",
        "完成提醒：开启": "Completion alerts: on",
        "完成提醒：关闭": "Completion alerts: off",
        "版本": "Version",
        "开始对话": "Start a conversation",
        "发送第一条消息。": "Send your first message.",
        "加载更早消息…": "Loading earlier messages…",
        "实时连接": "Live",
        "发送消息": "Message",
        "停止": "Stop",
        "深度求索中": "Thinking",
        "已连接": "Connected",
        "连接中…": "Connecting…",
        "重连中…": "Reconnecting…",
        "已断开": "Disconnected",
        "重试": "Retry",
        "断开连接": "Disconnect",
        "退出演示模式": "Exit demo mode",
        "开启完成提醒": "Enable completion alerts",
        "关闭完成提醒": "Disable completion alerts",
        "发送中…": "Sending…",
        "已发出，等待处理": "Sent · waiting",
        "已引导，正在继续": "Steering · continuing",
        "发送失败": "Send failed",
        "重新发送": "Resend",
        "复制整条消息": "Copy message",
        "引用这条消息": "Quote message",
        "取消引用": "Cancel quote",
        "引用": "Quote",
        "显示": "Show",
        "隐藏": "Hide",
        "复制": "Copy",
        "随机更换": "Regenerate",
        "自定义": "Custom",
        "密码不正确或已变更，请重新输入访问密码。": "PIN is incorrect or changed. Please enter it again.",
        "登录已过期或访问密码已变更，请重新输入密码连接。": "Session expired or PIN changed. Please reconnect.",
        "这条消息服务端没有收到，点消息下方「重新发送」可重试。": "The server did not receive this message. Tap Resend below.",
        "过程": "Steps",
        "步": "steps",
        "待发送": "Pending",
        "已复制": "Copied",
        "访问密码": "Access PIN",
        "删除连接": "Delete connection",
        "粘贴": "Paste",
        "断开与电脑的连接？": "Disconnect from your computer?",
        "断开后需要重新扫码配对（或输入访问密码）才能再次连接。": "After disconnecting you must scan the pairing QR again (or enter the access PIN) to reconnect.",
        "登录已过期（DSH 可能重启过），请重新扫码配对或输入访问密码。": "Your session expired (DSH may have restarted). Scan the pairing QR again or enter the access PIN.",
        "推荐": "Recommended",
        "扫码连接电脑": "Scan to connect",
        "扫一扫，连接电脑": "Scan QR to connect",
        "在电脑上打开 DSH → 设置 →「手机访问（iOS）」": "On your Mac, open DSH → Settings → Phone access (iOS)",
        "用本 App 扫描设置页上的二维码": "Scan the QR code from that page with this app",
        "自动连接，无需输入密码": "Connects automatically, no password needed",
        "或手动连接（输入地址与密码）": "Or connect manually (address + password)",
        "方式一（推荐）：Tailscale": "Option 1 (recommended): Tailscale",
        "电脑装 Tailscale + dsh-pocket-ios 连接器，手机装 Tailscale 和本 App；扫码即连，地址固定": "Install Tailscale + the dsh-pocket-ios connector on your Mac, Tailscale and this app on your phone; scan to connect, fixed address",
        "方式二：dsh-pocket": "Option 2: dsh-pocket",
        "电脑装 dsh-pocket 插件（可选再加 dsh-pocket-ios 连接器）；扫它的局域网/公网二维码后输入访问密码": "Install the dsh-pocket plugin on your Mac (optionally add the dsh-pocket-ios connector); scan its LAN/public QR and enter the access PIN",
        "按你选的路线装好对应插件（方式一：dsh-pocket-ios；方式二：dsh-pocket）": "Install the plugin for the option you picked (Option 1: dsh-pocket-ios; Option 2: dsh-pocket)",
        "打开电脑 DSH → 设置 → 手机访问": "Open DSH on your Mac → Settings → Phone access",
        "扫码：方式一自动连接；方式二输入访问密码": "Scan: Option 1 connects automatically; Option 2 asks for the access PIN",
        "已填入地址，请输入电脑上显示的访问密码（方式二）": "Address filled in. Enter the access PIN shown on your Mac (Option 2).",
        "准备（二选一）": "Before you start (pick one)",
        "Tailscale（推荐）": "Tailscale (recommended)",
        "Mac 和 iPhone 都安装并登录同一账号：地址固定、连接更稳定，换 Wi-Fi/切 4G 不用重新扫码": "Install Tailscale on both your Mac and iPhone with the same account: fixed address, more stable, no rescanning when switching networks",
        "dsh-pocket 插件": "dsh-pocket plugin",
        "在 Mac 的 DSH 插件市场安装 dsh-pocket，提供局域网/公网二维码；适合同一 Wi-Fi 或使用代理网络的场景": "Install dsh-pocket from the DSH plugin market: gives LAN/public QR codes; good for same-Wi-Fi or proxy setups",
        "然后": "Then",
        "在 Mac 上安装 dsh-pocket-ios 插件（提供「手机访问（iOS）」设置页）": "Install the dsh-pocket-ios plugin on your Mac (adds the Phone access (iOS) settings page)",
        "打开 DSH → 设置 →「手机访问（iOS）」": "Open DSH → Settings → Phone access (iOS)",
        "用本 App 扫描该页面上的二维码": "Scan the QR code on that page with this app",
        "访问密码（扫码连接可跳过）": "Access PIN (optional when scanning)",

        "删除连接？": "Delete this connection?",
        "删除": "Delete",
        "取消": "Cancel",
        "局域网": "LAN",
        "公网": "Public",
        "未连接": "Not connected",
        "正在连接": "Connecting",
        "正在重连": "Reconnecting",
        "重连中（第 %d 次）": "Reconnecting (%d)",
        "重连": "Retry",
        "新建会话": "New session",
        "切换连接": "Switch connection",
        "还没有会话": "No sessions yet",
        "创建会话后即可开始对话。": "Create a session to start chatting.",
        "完成": "Done",
        "演示模式 · 示例数据，未连接电脑": "Demo · sample data, not connected"
    ]
}

private let pocketLogger = Logger(subsystem: "com.ruska.dsh-pocket-ios", category: "conversation")

private func timingLog(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) DSH_TIMING \(message)"
    NSLog("%@", line)
}

/// Textual 没有公开清除选区的 API：直接定位当前第一响应者的文本输入视图，
/// 把它选中的范围置空（不重建视图，避免列表闪动/跳到底部）。
enum TextSelectionDismisser {
    static func clear() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if let responder = findFirstResponder(in: window), let input = responder as? UITextInput {
                    input.selectedTextRange = nil
                    responder.resignFirstResponder()
                    return
                }
            }
        }
    }

    private static func findFirstResponder(in view: UIView) -> UIResponder? {
        if view.isFirstResponder { return view }
        for subview in view.subviews {
            if let responder = findFirstResponder(in: subview) { return responder }
        }
        return nil
    }
}

/// 会话完成提醒：本地通知（前台也会弹 banner + 声音），支持在通知/Apple Watch 上直接文字回复。
final class CompletionNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CompletionNotifier()

    static let replyCategoryID = "DSH_REPLY"
    static let replyActionID = "DSH_REPLY_ACTION"
    static let sessionIdKey = "sessionId"

    /// 由 ConnectionModel 注入：收到通知回复时把文本发回对应会话。
    var onReply: ((String, String) async -> Void)?
    /// 由 ConnectionModel 注入：点击通知打开对应会话。
    var onOpenSession: ((String) -> Void)?

    private var configured = false

    func configure() {
        guard !configured else { return }
        configured = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // 通知展开/Apple Watch 上会出现「回复」输入框。
        let reply = UNTextInputNotificationAction(
            identifier: Self.replyActionID,
            title: "回复",
            options: [],
            textInputButtonTitle: "发送",
            textInputPlaceholder: "回复 DSH…"
        )
        let category = UNNotificationCategory(
            identifier: Self.replyCategoryID,
            actions: [reply],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(sessionId: String, title: String) {
        let content = UNMutableNotificationContent()
        content.title = "对话已完成"
        content.body = title.isEmpty ? "等待你的回复" : "「\(title)」等待你的回复"
        content.sound = .default
        content.categoryIdentifier = Self.replyCategoryID
        content.threadIdentifier = sessionId
        content.userInfo = [Self.sessionIdKey: sessionId, "title": title]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let sessionId = response.notification.request.content.userInfo[Self.sessionIdKey] as? String,
           !sessionId.isEmpty {
            onOpenSession?(sessionId)
            completionHandler()
            return
        }
        guard response.actionIdentifier == Self.replyActionID,
              let textResponse = response as? UNTextInputNotificationResponse else {
            completionHandler()
            return
        }
        let text = textResponse.userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let sessionId = response.notification.request.content.userInfo[Self.sessionIdKey] as? String,
              !sessionId.isEmpty else {
            completionHandler()
            return
        }
        Task { @MainActor in
            await self.onReply?(sessionId, text)
            completionHandler()
        }
    }
}

extension Notification.Name {
    static let dshPushTokenUpdated = Notification.Name("dsh-pocket.push-token-updated")
}

/// APNs device token 回调（SwiftUI 生命周期下用 delegate adaptor 接收）。
final class PushDelegate: NSObject, UIApplicationDelegate {
    static let tokenDefaultsKey = "dsh-pocket.apns-token"

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: Self.tokenDefaultsKey)
        NotificationCenter.default.post(name: .dshPushTokenUpdated, object: token)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("DSH_PUSH register failed: %@", error.localizedDescription)
    }
}

/// 访问密码存 Keychain：通知回复在后台/冷启动时需要自动重连。
enum PinKeychain {
    private static let service = "com.ruska.dsh-pocket-ios.pin"
    private static let account = "access-pin"

    static func save(_ pin: String) {
        guard !pin.isEmpty else { clear(); return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(pin.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let pin = String(data: data, encoding: .utf8) else { return nil }
        return pin
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@main
struct DSHPocketApp: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) private var pushDelegate
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
    /// 已 ACK、但消息体尚未进入历史的 rpcId；保留本地 pending，避免消息"闪一下消失"。
    var acknowledgedRpcIds: Set<String> = []
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
    private static let finishedAwaitingKey = "dsh-pocket.finished-awaiting"
    private static let completionAlertKey = "dsh-pocket.completion-alert"
    private static let runningSnapshotKey = "dsh-pocket.session-running"
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
    /// 当前屏幕上真正可见的会话（返回列表后会清空；不能用 selectedSession 判断，它不会清）。
    var visibleSessionId: String?
    /// session/list 的 running 状态机，用于识别"运行中 → 已结束"。
    private var completionTracker = SessionCompletionTracker(
        previous: (UserDefaults.standard.dictionary(forKey: ConnectionModel.runningSnapshotKey) as? [String: Bool]) ?? [:]
    )

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
    /// 置顶会话（服务端返回顺序：最近置顶在前）。
    var pinnedSessionIds: [String] = []
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
            case .idle: return L10n.t("未连接")
            case .demo: return L10n.t("演示模式")
            case .connecting: return L10n.t("正在连接")
            case .connected: return L10n.t("已连接")
            case .reconnecting(let attempt): return attempt > 1 ? L10n.tf("重连中（第 %d 次）", attempt) : L10n.t("正在重连")
            case .disconnected: return L10n.t("已断开")
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
    /// 已 ACK、等待消息落库的 rpcId（保留本地 pending，避免消息被吞）。
    private var acknowledgedSendRpcIds: Set<String> {
        get { activeConversation?.acknowledgedRpcIds ?? [] }
        set { activeConversation?.acknowledgedRpcIds = newValue }
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

    /// 带 `?token=` 的 DSH 认证 URL（浏览器复制出来的地址）：直接用 GET 换 cookie，无需密码。
    var pendingLoginToken: String?
    /// 扫码得到的一次性配对 token（免密码登录）。
    var pendingPairToken: String?

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
            serverAddress = url.absoluteString
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "地址格式无效。"
            recordDiagnostic("地址校验失败：\(serverAddress.debugDescription)")
            return
        }
        recordDiagnostic("开始连接：\(url.absoluteString)")
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

    /// 引用一条消息后递增，用于让输入框自动聚焦。
    var focusComposerTick = 0


    struct PendingQuote: Identifiable, Equatable {
        let id: String
        let sequence: Int
        let sender: String
        let text: String
    }

    /// 输入框上方显示的"正在引用"状态；发送时转成 DSH 原生 Markdown 引用块。
    var pendingQuote: PendingQuote?

    @MainActor
    func beginQuote(_ message: PocketMessage) {
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            pendingQuote = PendingQuote(
                id: message.id,
            sequence: message.sequence,
                sender: message.isUser ? "你" : "DSH",
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
    private func quotedPrefix(for quote: PendingQuote) -> String {
        let lines = quote.text.split(separator: "\n", omittingEmptySubsequences: false)
        let quoted = lines.map { "> \($0)" }.joined(separator: "\n")
        return quoted + "\n\n"
    }

    /// APNs device token：登录成功后注册到插件，用于后台完成推送。
    var pushToken: String? = UserDefaults.standard.string(forKey: PushDelegate.tokenDefaultsKey)
    private var pushTokenObserver: NSObjectProtocol?

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
        if pin.isEmpty, let savedPin = PinKeychain.load() { pin = savedPin }
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

    enum MarkdownSegment: Equatable {
        case text(String)
        case image(URL, caption: String?)
    }

    /// 把回复切成有序片段：文本段与图片段交替，图片按 Markdown 中的原位置渲染。
    func markdownSegments(_ markdown: String) -> [MarkdownSegment] {
        guard markdown.contains("![") else { return [.text(markdown)] }
        var segments: [MarkdownSegment] = []
        var buffer: [String] = []
        let regex = try? NSRegularExpression(pattern: #"^!\[([^\]]*)\]\(([^)\s]+)\)$"#)

        func flushText() {
            let joined = buffer.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.text(joined))
            }
            buffer.removeAll()
        }

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let regex,
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let captionRange = Range(match.range(at: 1), in: trimmed),
               let destinationRange = Range(match.range(at: 2), in: trimmed) {
                let caption = String(trimmed[captionRange])
                let destination = String(trimmed[destinationRange])
                if let url = markdownImageURL(for: destination) {
                    flushText()
                    segments.append(.image(url, caption: caption.isEmpty ? nil : caption))
                    continue
                }
            }
            buffer.append(line)
        }
        flushText()
        return segments.isEmpty ? [.text(markdown)] : segments
    }

    private func markdownImageURL(for destination: String) -> URL? {
        if let url = URL(string: destination),
           let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            return url
        }
        guard let base = try? Self.serverURL(from: serverAddress) else { return nil }
        var raw = destination.removingPercentEncoding ?? destination
        if raw.hasPrefix("file://") { raw = String(raw.dropFirst("file://".count)) }
        else if raw.hasPrefix("file:") { raw = String(raw.dropFirst("file:".count)) }
        guard !raw.isEmpty else { return nil }
        let absolute: String
        if raw.hasPrefix("/") {
            absolute = raw
        } else if let cwd = selectedSession?.cwd, cwd.hasPrefix("/") {
            absolute = URL(fileURLWithPath: cwd).appendingPathComponent(raw).standardized.path
        } else {
            return nil
        }
        var components = URLComponents(url: base.appending(path: "api/file"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "path", value: absolute)]
        return components?.url
    }

    /// 会话列表的 updatedAt 可能是毫秒或秒，统一成 Date。
    private static func dateFromSessionUpdatedAt(_ value: TimeInterval) -> Date {
        let seconds = value > 10_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }

    /// 给已保存地址设置/清除自定义标签（如「公司」「家」）。
    /// 删除一条已保存的连接（只删记录，不影响当前正在使用的地址）。
    @MainActor
    func removeEndpoint(_ address: String) {
        savedEndpoints.removeAll { $0.address == address }
        if let data = try? JSONEncoder().encode(savedEndpoints) {
            UserDefaults.standard.set(data, forKey: Self.savedEndpointsKey)
        }
    }

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
        PocketSession(sessionId: "demo-1", updatedAt: Date().timeIntervalSince1970 - 60, running: false, blank: false,
                      title: "做一个 iOS 版 DSH", cwd: "~/projects/ios-client"),
        PocketSession(sessionId: "demo-2", updatedAt: Date().timeIntervalSince1970 - 3600, running: false, blank: false,
                      title: "插件市场里有什么好玩的", cwd: "~/projects/dsh"),
        PocketSession(sessionId: "demo-3", updatedAt: Date().timeIntervalSince1970 - 7200, running: false, blank: false,
                      title: "规划东京 5 天行程", cwd: "~/Documents/旅行"),
        PocketSession(sessionId: "demo-4", updatedAt: Date().timeIntervalSince1970 - 86400, running: false, blank: false,
                      title: "这份体检报告怎么看", cwd: "~/Documents/健康"),
        PocketSession(sessionId: "demo-5", updatedAt: Date().timeIntervalSince1970 - 172800, running: false, blank: false,
                      title: "把会议记录变成行动项", cwd: "~/Documents/工作")
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
        // 演示模式也要保留用户消息（与真实发送一致），否则气泡会消失。
        var nextSequence = (messages.map(\.sequence).max() ?? 0) + 1
        messages.append(PocketMessage(demoText: text, isUser: true, sequence: nextSequence))
        nextSequence += 1
        messages.append(PocketMessage(
            demoText: "（演示模式）这是内置的示例回复，不会真正调用模型。\n\n连接电脑后，消息会发给本机的 DSH，助手回复与工具过程会实时出现在这里。",
            isUser: false, sequence: nextSequence))
        messages.sort { $0.sequence < $1.sequence }
    }

    private static func demoMessages(for sessionId: String) -> [PocketMessage] {
        switch sessionId {
        case "demo-1":
            return [
                PocketMessage(demoText: "帮我做一个 iOS 版的 DSH：要能连我电脑上的会话，原生客户端，不要网页套壳。",
                              isUser: true, sequence: 1),
                PocketMessage(demoText: "可以。DSH 讲究「万物皆插件」，我先去插件市场找现成能力，再组装起来。",
                              isUser: false, sequence: 2),
                PocketMessage(demoText: """
                搞定了，整个客户端是这样拼出来的：

                | 层 | 插件 | 作用 |
                | --- | --- | --- |
                | 连接 | dsh-pocket-ios | 把手机接到电脑上的 DSH |
                | 用量 | dsh-usage | 余额与 Token 统计 |
                | 转写 | parse-convert | 语音/链接转文字 |

                ### 已经完成

                - 原生 SwiftUI 客户端：会话、实时流、图片、Markdown
                - 扫码即连，局域网 / Tailscale / 公网三种通道
                - 模拟器已跑通，会话历史和电脑端实时同步

                想再加什么能力，直接去插件市场里装一个就行。
                """, isUser: false, sequence: 7)
            ]
        case "demo-2":
            return [
                PocketMessage(demoText: "DSH 的插件市场里都有什么好玩的？", isUser: true, sequence: 1),
                PocketMessage(demoText: """
                DSH 的理念就是「万物皆插件」：连接、工具、界面、技能都能单独装卸。

                | 类别 | 插件举例 | 能做什么 |
                | --- | --- | --- |
                | 连接 | dsh-pocket-ios | 手机远程用电脑上的 DSH |
                | 用量 | dsh-usage | 余额、Token、花费趋势 |
                | 转写 | parse-convert | 视频/音频转文字、提取字幕 |
                | 设计 | huashu-design | 高保真原型、幻灯片、动画 |

                装插件不用改启动器，重启后设置页里就出现新能力。
                """, isUser: false, sequence: 2)
            ]
        case "demo-3":
            return [
                PocketMessage(demoText: "帮我规划东京 5 天行程，住新宿，喜欢咖啡和建筑，不要太赶。",
                              isUser: true, sequence: 1),
                PocketMessage(demoText: """
                按「半天一个重点」排，留出咖啡和散步时间：

                | 天 | 上午 | 下午 | 晚上 |
                | --- | --- | --- | --- |
                | D1 | 抵达 / 新宿 | 都厅展望台 | 思い出横丁 |
                | D2 | 浅草寺 | 隅田川散步 | 神保町旧书店 |
                | D3 | 表参道建筑 | 青山咖啡 | 六本木夜景 |
                | D4 | 代官山 | 中目黑 | 目黑川 |
                | D5 | 筑地 | 银座 | 返程 |

                **小建议**：买一张 Suica，咖啡店按区域就近排，别跨区折返。
                """, isUser: false, sequence: 2)
            ]
        case "demo-4":
            return [
                PocketMessage(demoText: "帮我看下这份体检报告，几个指标是什么意思？",
                              isUser: true, sequence: 1, localImages: [demoPicture]),
                PocketMessage(demoText: """
                整体问题不大，重点关注这三项：

                | 指标 | 结果 | 解读 |
                | --- | --- | --- |
                | 总胆固醇 | 略高 | 先调整饮食，3 个月复查 |
                | 尿酸 | 偏高 | 少喝含糖饮料，多喝水 |
                | 维D | 偏低 | 多晒太阳，必要时补充 |

                其余指标在正常范围。建议把报告带去门诊让医生结合症状判断。
                """, isUser: false, sequence: 2)
            ]
        default:
            return [
                PocketMessage(demoText: "把今天的会议记录整理成行动项，标上负责人。", isUser: true, sequence: 1),
                PocketMessage(demoText: """
                整理好了：

                1. **周三前** 出 Q2 数据口径文档 — @小王
                2. **周四** 和设计确认新版首页 — @小李
                3. **下周一** 给客户发演示环境 — @我
                4. 待定：是否接入第三方登录

                原始记录里没写负责人的两条，我标成「待定」了，确认后我再补。
                """, isUser: false, sequence: 2)
            ]
        }
    }

    private static func demoSteps(for sessionId: String) -> [PocketStep] {
        guard sessionId == "demo-1" else { return [] }
        return [
            PocketStep(id: "demo-step-1", sequence: 3, turn: 1, number: 1,
                       name: "search", detail: "插件市场 · ios",
                       resultText: "dsh-pocket-ios（连接） · dsh-usage（用量） · huashu-design（设计）",
                       finished: true),
            PocketStep(id: "demo-step-2", sequence: 4, turn: 1, number: 2,
                       name: "bash", detail: "dsh plugin add dsh-pocket-ios",
                       resultText: "installed dsh-pocket-ios@0.2.1", finished: true),
            PocketStep(id: "demo-step-3", sequence: 5, turn: 1, number: 3,
                       name: "write", detail: "生成 SwiftUI 工程 + DSHKit",
                       resultText: "App target / DSHKit 已生成", finished: true),
            PocketStep(id: "demo-step-4", sequence: 6, turn: 1, number: 4,
                       name: "bash", detail: "xcodebuild → BUILD SUCCEEDED",
                       resultText: "模拟器验证通过，会话已同步", finished: true)
        ]
    }


    // MARK: - 完成提醒（红点 / 声音 / 通知）

    /// 用最新 session 列表更新 running 状态机，识别"运行中 → 已结束"的会话。
    @MainActor
    private func detectSessionCompletions() {
        let latest = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionId, $0.running) })
        let completed = completionTracker.update(latest: latest)
        UserDefaults.standard.set(latest, forKey: Self.runningSnapshotKey)
        recordDiagnostic("可用会话刷新：\(latest.count) 个，完成事件 \(completed.count) 个")

        // 重新开始运行的会话不再算"等待回复"。
        for session in sessions where session.running {
            finishedAwaitingSessionIds.remove(session.sessionId)
        }

        guard !completed.isEmpty else { return }
        for sessionId in completed {
            guard let session = sessions.first(where: { $0.sessionId == sessionId }) else { continue }
            let viewing = visibleSessionId == sessionId && isAppActive
            if viewing {
                finishedAwaitingSessionIds.remove(sessionId)
            } else {
                finishedAwaitingSessionIds.insert(sessionId)
                if completionAlertsEnabled { playCompletionFeedback(for: session) }
            }
        }
        persistFinishedAwaiting()
    }

    @MainActor
    func markFinishedAwaitingRead(_ sessionId: String) {
        if finishedAwaitingSessionIds.remove(sessionId) != nil {
            persistFinishedAwaiting()
        }
    }

    @MainActor
    func toggleCompletionAlerts() {
        completionAlertsEnabled.toggle()
        UserDefaults.standard.set(completionAlertsEnabled, forKey: Self.completionAlertKey)
        if completionAlertsEnabled,
           ProcessInfo.processInfo.environment["DSH_NO_NOTIF_PROMPT"] != "1" {
            CompletionNotifier.shared.requestPermission()
            Task { await syncPushRegistration() }
        } else if let token = pushToken {
            Task { _ = try? await rpc("push.unregister", args: ["token": token]) }
        }
        recordDiagnostic("完成提醒：\(completionAlertsEnabled ? "开启" : "关闭")")
    }

    @MainActor
    private func playCompletionFeedback(for session: PocketSession) {
        CompletionNotifier.shared.notify(sessionId: session.sessionId, title: session.displayTitle)
        // 通知被关闭时也有声音兜底。
        AudioServicesPlaySystemSound(1007)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        recordDiagnostic("完成提醒：\(session.displayTitle)")
    }

    @MainActor
    private func persistFinishedAwaiting() {
        UserDefaults.standard.set(Array(finishedAwaitingSessionIds), forKey: Self.finishedAwaitingKey)
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
            detectSessionCompletions()
            errorMessage = nil
            recordDiagnostic("会话列表刷新：\(sessions.count) 个，隐藏归档 \(archivedSessionIds.count) 个")
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            if let authError = error as? ConnectionError,
               case .server(let status) = authError,
               TimelineOrdering.isUnauthorized(statusCode: status) {
                recordDiagnostic("会话列表 401：登录已失效")
                handleAuthExpired()
                return
            }
            recordDiagnostic("会话列表刷新失败：\(error.localizedDescription)")
            if isStaleTunnelError(error) {
                applyConnectError(error)
            } else {
                errorMessage = "无法读取会话：\(error.localizedDescription)"
            }
        }
    }

    /// 列表展示顺序：置顶在前（最近置顶优先），其余保持服务端顺序。
    var displaySessions: [PocketSession] {
        guard !pinnedSessionIds.isEmpty else { return sessions }
        let pinned = pinnedSessionIds.compactMap { id in sessions.first { $0.sessionId == id } }
        let rest = sessions.filter { !pinnedSessionIds.contains($0.sessionId) }
        return pinned + rest
    }

    private func fetchSessions() async throws -> [PocketSession] {
        let value = try await rpc("session/list", args: ["_request": ["excludeArchived": true]])
        let items = value["items"] as? [[String: Any]] ?? []
        let sessions = items.compactMap(PocketSession.init(json:))
        let archived: Set<String>
        if value["archivedSessionsExcluded"] as? Bool == true {
            archived = []
            pinnedSessionIds = []
        } else {
            let flags = try await fetchWorkspaceSessionFlags()
            archived = flags.archived
            pinnedSessionIds = flags.pinned
        }
        archivedSessionIds = archived
        // 与 DSH 桌面端侧边栏保持一致：隐藏已归档、subagent 子会话和空会话，
        // 这样 iOS 列表数量和 Mac 端看到的数量一致。
        return sessions.filter { !archived.contains($0.sessionId) && !$0.isSubagent && !$0.isHiddenFromList }
    }

    private func fetchWorkspaceSessionFlags() async throws -> (archived: Set<String>, pinned: [String]) {
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
            let pinned = baseline["pinnedSessionIds"] as? [String] ?? []
            return (Set(archived), pinned)
        }
    }

    /// 最近一次被归档的会话（用于列表底部「撤销」）。
    var lastArchivedSession: PocketSession?

    /// 撤销最近一次归档。
    @MainActor
    func undoArchive() async {
        guard let session = lastArchivedSession else { return }
        lastArchivedSession = nil
        if isDemoMode {
            archivedSessionIds.remove(session.sessionId)
            await loadSessions(silently: true)
            return
        }
        do {
            _ = try await rpc("workspace/unarchiveSession", args: ["request": ["sessionId": session.sessionId]])
            archivedSessionIds.remove(session.sessionId)
            await loadSessions(silently: true)
        } catch {
            errorMessage = "撤销归档失败：\(error.localizedDescription)"
        }
    }

    /// 置顶 / 取消置顶（服务端 workspace/pinSession，桌面端同步）。
    @MainActor
    func togglePin(_ session: PocketSession) async {
        let pinned = pinnedSessionIds.contains(session.sessionId)
        if isDemoMode {
            if pinned { pinnedSessionIds.removeAll { $0 == session.sessionId } }
            else { pinnedSessionIds.insert(session.sessionId, at: 0) }
            return
        }
        do {
            let endpoint = pinned ? "workspace/unpinSession" : "workspace/pinSession"
            let value = try await rpc(endpoint, args: ["request": ["sessionId": session.sessionId]])
            if let list = value["pinnedSessionIds"] as? [String] {
                pinnedSessionIds = list
            } else if pinned {
                pinnedSessionIds.removeAll { $0 == session.sessionId }
            } else {
                pinnedSessionIds.insert(session.sessionId, at: 0)
            }
        } catch {
            errorMessage = "置顶失败：\(error.localizedDescription)"
        }
    }

    /// 归档会话（从列表移除，桌面端同步隐藏）。
    @MainActor
    func archive(_ session: PocketSession) async {
        if isDemoMode {
            sessions.removeAll { $0.sessionId == session.sessionId }
            archivedSessionIds.insert(session.sessionId)
            pinnedSessionIds.removeAll { $0 == session.sessionId }
            return
        }
        do {
            let value = try await rpc("workspace/archiveSession", args: ["request": [
                "sessionId": session.sessionId,
                "stopActivity": false
            ]])
            if let ids = value["archivedSessionIds"] as? [String] {
                archivedSessionIds = Set(ids)
            } else {
                archivedSessionIds.insert(session.sessionId)
            }
            sessions.removeAll { $0.sessionId == session.sessionId }
            pinnedSessionIds.removeAll { $0 == session.sessionId }
            lastArchivedSession = session
            if selectedSession?.sessionId == session.sessionId { selectedSession = nil }
        } catch {
            errorMessage = "归档失败：\(error.localizedDescription)"
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
        pruneStaleOutbox()
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
        markFinishedAwaitingRead(session.sessionId)
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
            let olderLoads = DebugLaunch.loadOlderCount
            if olderLoads > 0 {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    for _ in 0..<olderLoads {
                        self?.loadOlderMessages()
                        try? await Task.sleep(for: .seconds(2))
                    }
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
            confirmInboxOutbox(in: records)
            isLoadingConversation = false
            if wasEmpty { requestScrollToBottom() }
        } catch {
            if error is CancellationError { return }
            guard selectedSession?.sessionId == session.sessionId, messages.isEmpty else { return }
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            if let authError = error as? ConnectionError,
               case .server(let status) = authError,
               TimelineOrdering.isUnauthorized(statusCode: status) {
                handleAuthExpired()
                return
            }
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
                // 兜底：服务端没回填 rpcId（steer 偶发丢确认），但本次新出现了同文本用户消息。
                if incoming.contains(where: {
                    $0.isUser && !$0.isPending && $0.rpcId == nil
                        && $0.text == message.text && $0.sequence > previousMaxConfirmed
                }) {
                    acknowledgedSendRpcIds.remove(rpcId)
                    confirmOutbox(rpcIds: [rpcId])
                    return false
                }
                let decision = TimelineOrdering.pendingDecision(
                    rpcId: rpcId,
                    hasRealMessageWithSameRpcId: incoming.contains {
                        !$0.isPending && $0.rpcId?.lowercased() == rpcId.lowercased()
                    },
                    acknowledgedInIncoming: incomingRpcIds.contains(rpcId.lowercased()),
                    isFailed: failedSendRpcIds.contains(rpcId),
                    inOutbox: outboxEntries.contains { $0.id.lowercased() == rpcId.lowercased() },
                    isAcknowledged: acknowledgedSendRpcIds.contains(rpcId)
                )
                switch decision {
                case .replaceWithReal:
                    acknowledgedSendRpcIds.remove(rpcId)
                    if failedSendRpcIds.remove(rpcId) != nil { conversationError = nil }
                    return false
                case .acknowledgeAndKeep:
                    acknowledgedSendRpcIds.insert(rpcId)
                    if failedSendRpcIds.remove(rpcId) != nil { conversationError = nil }
                    return true
                case .keep:
                    return true
                case .dropStale:
                    return false
                }
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
        pruneStaleOutbox()
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

    /// 从历史记录里提取 steer 的 inbox rpcId（agent/inbox/spliced），用于确认发件箱。
    private func inboxRpcIds(in records: [[String: Any]]) -> Set<String> {
        var ids = Set<String>()
        for record in records {
            guard let event = record["event"] as? [String: Any],
                  event["type"] as? String == "agent/inbox/spliced",
                  let data = event["data"] as? [String: Any],
                  let inserted = data["inserted"] as? [[String: Any]] else { continue }
            for item in inserted {
                if let rpcId = (item["source"] as? [String: Any])?["rpcId"] as? String, !rpcId.isEmpty {
                    ids.insert(rpcId.lowercased())
                }
            }
        }
        return ids
    }

    @MainActor
    private func confirmInboxOutbox(in records: [[String: Any]]) {
        let ids = inboxRpcIds(in: records)
        guard !ids.isEmpty else { return }
        // 先登记为"已确认但消息体尚未落库"，mergeMessages 会保留本地 pending，
        // 等真实 user/message 出现再替换；否则消息会闪一下消失。
        acknowledgedSendRpcIds.formUnion(ids)
        confirmOutbox(rpcIds: ids)
        ackedSendRpcIds.subtract(ids)
        failedSendRpcIds.subtract(ids)
        if conversationError?.contains("服务端没有收到") == true { conversationError = nil }
        recordDiagnostic("历史中确认 steer 已送达（\(ids.count) 条）")
    }

    /// 发件箱超时清理：
    /// - 已 ACK 的旧条目 → 视为已送达，移除（避免 steer 永远"发送中"）；
    /// - 未 ACK 且超时的 → 标为失败，让用户看到「重新发送」而不是无限转圈。
    @MainActor
    private func pruneStaleOutbox(maxAge: TimeInterval = 120) {
        loadOutboxIfNeeded()
        let now = Date().timeIntervalSince1970
        var changed = false
        for entry in outboxEntries where now - entry.createdAt > maxAge {
            let rpcId = entry.id.lowercased()
            if ackedSendRpcIds.contains(rpcId) || ackedSendRpcIds.contains(entry.id) {
                confirmOutbox(rpcIds: [rpcId])
                ackedSendRpcIds.remove(rpcId)
                recordDiagnostic("发件箱超时清理（已 ACK，视为送达）：\(rpcId)")
            } else {
                failedSendRpcIds.insert(rpcId)
                removeOutbox(rpcIds: [rpcId])
                recordDiagnostic("发件箱超时清理（未确认，标为失败）：\(rpcId)")
            }
            changed = true
        }
        if changed { persistOutbox() }
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
        // 待发消息不能用 Int.max（会沉到「过程」行下面）；用发送时最后一条已确认消息的位置，
        // 这样它排在旧消息之后、发送之后产生的工具步骤之前。
        TimelineOrdering.sortKey(sequence: message.sequence,
                                 localSortKey: message.localSortKey,
                                 isPending: message.isPending)
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
        let sortedSteps = steps.sorted { $0.sequence < $1.sequence }
        // 助手文字消息（非 pending）是过程段之间的分隔点：桌面端会把工具活动拆成多段。
        let boundaries = messages
            .filter { !$0.isUser && !$0.isPending && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(\.sequence)
            .sorted()

        var groups: [PocketStepGroup] = []
        var current: [PocketStep] = []
        var lastSeq = Int.min
        var lastTurn: Int?

        func flush() {
            guard let first = current.first else { return }
            groups.append(PocketStepGroup(turn: first.turn, sequence: first.sequence, steps: current))
            current = []
        }

        for step in sortedSteps {
            let turnChanged = lastTurn != nil && step.turn != lastTurn
            let crossedText = boundaries.contains { $0 > lastSeq && $0 < step.sequence }
            if turnChanged || crossedText { flush() }
            current.append(step)
            lastSeq = step.sequence
            lastTurn = step.turn
        }
        flush()
        return groups
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

    /// 网络恢复后继续核验（最多 5 次，退避 5/10/20/40/60s）。
    private func scheduleSendReverification(session: PocketSession, requestId: String, attempt: Int) {
        guard attempt <= 5 else { return }
        let delay = [5.0, 10.0, 20.0, 40.0, 60.0][attempt - 1]
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self else { return }
            guard await MainActor.run(body: { self.ackedSendRpcIds.contains(requestId) }) else { return }
            switch await self.verifySendLanded(session: session, requestId: requestId) {
            case .landed:
                await MainActor.run {
                    self.confirmOutbox(rpcIds: [requestId])
                    self.ackedSendRpcIds.remove(requestId)
                    self.failedSendRpcIds.remove(requestId)
                    self.conversationError = nil
                    self.recordDiagnostic("发送延迟核验成功：\(requestId)")
                }
            case .absent:
                await MainActor.run {
                    self.failedSendRpcIds.insert(requestId)
                    self.conversationError = "这条消息服务端没有收到，点消息下方「重新发送」可重试。"
                }
            case .unreachable:
                self.scheduleSendReverification(session: session, requestId: requestId, attempt: attempt + 1)
            }
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
                confirmInboxOutbox(in: records)
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
                // 重连多次仍失败时探测登录态：DSH 重启后 browser-auth cookie 会失效，
                // WS 只会一直重连，必须回到连接页重新输入密码。
                if retryCount >= 1 {
                    do {
                        _ = try await fetchSessions()
                    } catch let authError as ConnectionError {
                        if case .server(401) = authError {
                            handleAuthExpired()
                            return
                        }
                    } catch { /* 其他网络错误继续重连 */ }
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
            confirmInboxOutbox(in: records)
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
                // steer 消息先进 agent inbox（spliced），这里也视为已送达，避免误报失败。
                if event["type"] as? String == "agent/inbox/spliced",
                   let data = event["data"] as? [String: Any],
                   let inserted = data["inserted"] as? [[String: Any]] {
                    let ids = Set(inserted.compactMap {
                        ($0["source"] as? [String: Any])?["rpcId"] as? String
                    }.map { $0.lowercased() })
                    if !ids.isEmpty {
                        confirmOutbox(rpcIds: ids)
                        ackedSendRpcIds.subtract(ids)
                        failedSendRpcIds.subtract(ids)
                        conversationError = nil
                        recordDiagnostic("steer 已进入收件箱（\(ids.count) 条），等待注入")
                    }
                }
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

    /// 登录失效（DSH 重启导致 cookie 失效 / 密码被改）：回到连接页并要求重新输入密码。
    @MainActor
    func handleAuthExpired() {
        guard !isDemoMode else { return }
        recordDiagnostic("登录已过期或密码已变更：返回连接页")
        isConnected = false
        pin = ""
        PinKeychain.clear()
        selectedSession = nil
        navigationPath = []
        activeConversation?.liveTask?.cancel()
        liveConnection = .disconnected(reason: "auth")
        errorMessage = L10n.t("登录已过期（DSH 可能重启过），请重新扫码配对或输入访问密码。")
    }

    /// 发送按钮入口：先确认当前打开的就是这个会话，避免消息发到别的 session。
    @MainActor
    func sendMessage(in session: PocketSession) {
        if selectedSession?.sessionId != session.sessionId {
            recordDiagnostic("发送前纠正会话：期望 \(session.displayTitle)")
            selectedSession = session
            open(session)
            // 继续发送，避免"点了发送但输入框内容还在、也没发出去"。
            sendMessage()
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
            // sendDemoMessage 自己会清空草稿；这里不能先清，否则它读不到文本。
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
        // 有引用时把原文作为 Markdown 引用块前置（DSH 协议层只接受文本/图片块）。
        var outgoingText = text
        if let quote = pendingQuote {
            outgoingText = quotedPrefix(for: quote) + text
            recordDiagnostic("发送带引用：引用 #\(quote.sequence)")
            pendingQuote = nil
        }
        // 立刻清空：不等异步 performSend 的 guard，也避免中文输入法把 marked text 留在框里。
        clearDraftImmediately()
        sendTask = Task { await self.performSend(text: outgoingText, attachments: attachments) }
    }

    /// 同步清空当前输入框 + 该会话的持久化草稿；下一轮 runloop 再清一次，兜住输入法回填。
    @MainActor
    private func clearDraftImmediately() {
        let conversation = activeConversation
        let sessionId = conversation?.sessionId ?? selectedSession?.sessionId
        conversation?.draft = ""
        conversation?.draftImages = []
        draft = ""
        draftImages = []
        if let sessionId { DraftStore.save("", for: sessionId) }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.activeConversation === conversation || conversation == nil {
                self.draft = ""
                self.draftImages = []
            }
        }
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
                                       bytes: $0.bytes ?? 0,
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
                                         bytes: $0.bytes ?? 0,
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

    /// 点击完成通知：连接后打开对应会话（找不到则落到会话列表）。
    @MainActor
    func openSessionFromNotification(sessionId: String) async {
        if !isConnected {
            if pin.isEmpty, let savedPin = PinKeychain.load() { pin = savedPin }
            if pin.isEmpty, let saved = UserDefaults.standard.string(forKey: Self.savedServerAddressKey), !saved.isEmpty {
                serverAddress = saved
            }
            await connect()
        }
        guard let session = sessions.first(where: { $0.sessionId == sessionId }) else {
            recordDiagnostic("通知打开会话失败：找不到 \(sessionId)")
            return
        }
        finishedAwaitingSessionIds.remove(sessionId)
        persistFinishedAwaiting()
        navigationPath = [session]
    }

    /// 登录成功后把 APNs token 注册到插件；通知权限未开启时先请求权限。
    @MainActor
    func syncPushRegistration() async {
        guard completionAlertsEnabled else {
            if let token = pushToken {
                _ = try? await rpc("push.unregister", args: ["token": token])
            }
            return
        }
        UIApplication.shared.registerForRemoteNotifications()
        guard let token = pushToken, isConnected else { return }
        do {
            _ = try await rpc("push.register", args: [
                "token": token,
                "environment": "sandbox",
                "bundleId": Bundle.main.bundleIdentifier ?? "",
                "deviceName": UIDevice.current.name
            ])
            recordDiagnostic("APNs token 已注册（\(token.suffix(6))）")
        } catch {
            recordDiagnostic("APNs token 注册失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    /// 通知 / Apple Watch 直接回复：把文本作为 prompt 发回指定会话。
    /// 冷启动时用 Keychain 里的密码自动重连；失败只记录诊断，不打断前台。
    func sendNotificationReply(sessionId: String, text: String) async {
        guard !text.isEmpty else { return }
        recordDiagnostic("通知回复：会话 \(sessionId)，\(text.count) 字")
        let background = UIApplication.shared.beginBackgroundTask(withName: "dsh-notification-reply")
        defer {
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
        }

        if !isConnected {
            if let saved = UserDefaults.standard.string(forKey: Self.savedServerAddressKey), !saved.isEmpty {
                serverAddress = saved
            }
            if pin.isEmpty, let savedPin = PinKeychain.load() { pin = savedPin }
            if pin.isEmpty {
                recordDiagnostic("通知回复失败：未连接且没有可用密码")
                return
            }
            await connect()
            guard isConnected else {
                recordDiagnostic("通知回复失败：自动重连未成功")
                return
            }
        }

        let running = sessions.first(where: { $0.sessionId == sessionId })?.running ?? false
        let mode = running ? "steer" : "queue"
        let requestId = UUID().uuidString.lowercased()
        do {
            _ = try await rpcWithRetry("session/prompt", args: ["request": [
                "requestId": requestId,
                "sessionId": sessionId,
                "mode": mode,
                "content": [["type": "text", "text": text]],
                "clientTimeZone": TimeZone.current.identifier
            ]])
            ackedSendRpcIds.insert(requestId)
            addOutbox(sessionId: sessionId, rpcId: requestId, text: text)
            if finishedAwaitingSessionIds.remove(sessionId) != nil { persistFinishedAwaiting() }
            recordDiagnostic("通知回复已发送（模式 \(mode)）")
        } catch {
            recordDiagnostic("通知回复发送失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    private func performSend(text: String, attachments: [PocketDraftImage]) async {
        guard let session = selectedSession, !isSending else { return }
        let sendConversation = conversations[session.sessionId]
        let lastSequence = messages.filter { !$0.isPending }.map(\.sequence).max() ?? -1
        let requestId = UUID().uuidString.lowercased()
        let sortAnchor = TimelineOrdering.pendingAnchor(
            messageMax: lastSequence,
            stepMax: steps.map(\.sequence).max() ?? -1
        )
        let pending = PocketMessage(pendingText: text, localImages: attachments.map(\.uiImage), rpcId: requestId, sortSequence: sortAnchor)
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
        if let sendConversation {
            sendConversation.draft = ""
            sendConversation.draftImages = []
        }
        DraftStore.save("", for: session.sessionId)
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
            _ = try await rpcWithRetry("session/prompt", args: ["request": [
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
            // 服务端 ACK 后如果还没收到确认，先主动核验一次（网络抖动时 WS/轮询可能错过确认），
            // 核验不到再标记失败，避免误报吓人。
            if ackedSendRpcIds.contains(requestId) && promptMode == "steer" {
                // steer 进入 agent inbox，后续会被注入成 user/message；
                // 此阶段核验不到是正常现象，绝不能标失败（显示"已送达，排队等待处理"）。
                if case .landed = await verifySendLanded(session: session, requestId: requestId) {
                    confirmOutbox(rpcIds: [requestId])
                    ackedSendRpcIds.remove(requestId)
                    failedSendRpcIds.remove(requestId)
                    conversationError = nil
                    recordDiagnostic("steer 已落库确认：\(requestId)")
                } else {
                    conversationError = nil
                    recordDiagnostic("steer 已 ACK，等待注入为 user/message：\(requestId)")
                }
            } else if ackedSendRpcIds.contains(requestId) {
                switch await verifySendLanded(session: session, requestId: requestId) {
                case .landed:
                    confirmOutbox(rpcIds: [requestId])
                    ackedSendRpcIds.remove(requestId)
                    failedSendRpcIds.remove(requestId)
                    conversationError = nil
                    recordDiagnostic("发送核验成功：\(requestId)")
                case .absent:
                    failedSendRpcIds.insert(requestId)
                    conversationError = "这条消息服务端没有收到，点消息下方「重新发送」可重试（按 requestId 去重，不会重复）。"
                    recordDiagnostic("发送核验失败（服务端无此消息）：\(requestId)")
                case .unreachable:
                    // 网络抖动导致核验请求本身失败：不能误报失败，保持"已发出，等待处理"，后台再核验。
                    recordDiagnostic("发送核验网络不可达，稍后重试：\(requestId)")
                    scheduleSendReverification(session: session, requestId: requestId, attempt: 1)
                }
            }
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                removeOutbox(rpcIds: [requestId])
                messages.removeAll { $0.id == pending.id }
                return
            }
            if let authError = error as? ConnectionError, case .server(401) = authError {
                removeOutbox(rpcIds: [requestId])
                messages.removeAll { $0.id == pending.id }
                handleAuthExpired()
                return
            }
            // 保留气泡并标记失败，用户可直接重发（不再把文字塞回输入框）。
            failedSendRpcIds.insert(requestId)
            conversationError = "发送失败：\(error.localizedDescription)（点消息气泡下方「重新发送」可重试）"
        }
    }

    /// 对网络抖动做有限重试（仅用于幂等请求：session/prompt 按 requestId 去重、session/page 只读）。
    private func rpcWithRetry(_ endpoint: String, args: [String: Any], attempts: Int = 3) async throws -> [String: Any] {
        var lastError: Error?
        for attempt in 0..<attempts {
            if Task.isCancelled { throw CancellationError() }
            do {
                return try await rpc(endpoint, args: args)
            } catch {
                lastError = error
                guard isTransientNetworkError(error), attempt < attempts - 1 else { throw error }
                await MainActor.run { [weak self] in
                    self?.recordDiagnostic("网络抖动，重试 \(endpoint)（第 \(attempt + 2) 次）")
                }
                try? await Task.sleep(for: .milliseconds(attempt == 0 ? 800 : 2000))
            }
        }
        throw lastError ?? ConnectionError.server(-1)
    }

    private func isTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private enum SendVerification {
        case landed
        case absent        // 请求成功但历史里确实没有这条消息
        case unreachable   // 网络失败，无法判断——不能当作失败提示用户
    }

    /// 主动核验消息是否真的落库：在最近会话历史里按 rpcId 精确查找。
    private func verifySendLanded(session: PocketSession, requestId: String) async -> SendVerification {
        var sawReachableResponse = false
        for attempt in 0..<4 {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(attempt == 1 ? 1 : attempt == 2 ? 2 : 4))
            }
            guard let value = try? await rpc("session/page", args: ["request": [
                "address": ["kind": "session", "sessionId": session.sessionId],
                "maxMessages": 30
            ]]) else { continue }
            sawReachableResponse = true
            let records = value["records"] as? [[String: Any]] ?? []
            for record in records {
                guard let event = record["event"] as? [String: Any],
                      let data = event["data"] as? [String: Any] else { continue }
                // 正常落库：user/message 带 rpcId
                if event["type"] as? String == "user/message",
                   let source = data["source"] as? [String: Any],
                   let rpcId = source["rpcId"] as? String,
                   RPCId.matches(rpcId, requestId) {
                    return .landed
                }
                // 生成中 steer：先进入 agent inbox（agent/inbox/spliced），
                // 不会立刻变成 user/message；这里也视为"已送达，排队等待处理"。
                if event["type"] as? String == "agent/inbox/spliced",
                   let inserted = data["inserted"] as? [[String: Any]] {
                    for item in inserted {
                        guard let source = item["source"] as? [String: Any],
                              let rpcId = source["rpcId"] as? String else { continue }
                        if RPCId.matches(rpcId, requestId) { return .landed }
                    }
                }
            }
        }
        return sawReachableResponse ? .absent : .unreachable
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
            case .lan: return L10n.t("局域网")
            case .publicNetwork: return L10n.t("公网")
            case .custom: return L10n.t("自定义")
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
    /// 待发消息在会话里的显示排序位置（发送时刻最后一条已确认消息的 sequence）。
    var localSortKey: Int? = nil
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

    init(pendingText: String, localImages: [UIImage] = [], rpcId: String? = nil, sortSequence: Int? = nil) {
        self.id = "pending-\(UUID().uuidString)"
        self.sequence = Int.max
        self.localSortKey = sortSequence
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
    init(attachmentId: String, mediaType: String? = nil, bytes: Int = 0, width: Int? = nil,
         height: Int? = nil, name: String? = nil) {
        self.attachmentId = attachmentId
        self.mediaType = mediaType ?? "image/jpeg"
        self.bytes = bytes
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

    /// 正在执行时的进行时文案（Mac 端那种"正在运行命令…"的实时感）。
    var runningLabel: String {
        switch name {
        case "bash", "exec_command", "pwsh", "write_stdin", "terminal_read", "terminal_open": "正在运行命令…"
        case "read": "正在读取文件…"
        case "read_image": "正在查看图片…"
        case "grep", "glob", "search": "正在搜索…"
        case "write": "正在写入文件…"
        case "edit", "apply_patch": "正在编辑文件…"
        case "web_search": "正在搜索网页…"
        case "web_fetch": "正在打开网页…"
        case "job_output": "正在读取任务输出…"
        case "todo_write": "正在更新待办…"
        case "ask_user_question": "正在等待你的选择…"
        case "present": "正在展示…"
        case "subagent", "subagent_fork": "正在运行子任务…"
        default: "正在执行 \(name)…"
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
    /// 同一 turn 里可能有多段"过程"（被助手文字分隔），用起始 seq 作为唯一 id。
    var id: String { "steps-\(sequence)" }
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
        case .invalidPin: L10n.t("密码不正确或已变更，请重新输入访问密码。")
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
    static var loadOlderCount: Int {
        guard let raw = environment["DSH_LOAD_OLDER"] else { return 0 }
        return Int(raw) ?? (raw == "1" ? 1 : 0)
    }
    static var showConnect: Bool { environment["DSH_CONNECT"] == "1" }
    static var attachPath: String? { environment["DSH_ATTACH"] ?? value(for: "--dsh-attach") }
    static var demoMode: Bool { environment["DSH_DEMO"] == "1" }
    /// 截图/演示用：隐藏「演示模式」状态行，让界面更接近真实使用。
    static var hideDemoBanner: Bool { environment["DSH_HIDE_DEMO_BANNER"] == "1" }
    /// 截图用：打开会话后自动展开所有「过程」。
    static var expandSteps: Bool { environment["DSH_EXPAND_STEPS"] == "1" }
    /// 截图用：打开会话后滚动到顶部。
    static var scrollToTop: Bool { environment["DSH_SCROLL_TO_TOP"] == "1" }

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
    @State private var languageRevision = 0
    @State private var showingAppSettings = false
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAppSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(L10n.t("设置"))
                }
            }
            .sheet(isPresented: $showingAppSettings) { AppSettingsSheet(model: model) }
            .id(languageRevision)
        }
        .tint(Color(red: 0.08, green: 0.48, blue: 0.37))
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageChanged)) { _ in
            languageRevision &+= 1
        }
        .task { await model.restoreConnection() }
        .onChange(of: scenePhase) { _, phase in
            model.isAppActive = (phase == .active)
            // 回到前台只静默刷新列表，不自动切换网络，避免打断当前会话。
            guard phase == .active, model.isConnected else { return }
            Task { await model.loadSessions(silently: true) }
        }
        .task(id: model.isConnected) {
            // 周期刷新会话列表，识别"其他会话跑完了"（完成提醒的红点/通知）。
            guard model.isConnected, !model.isDemoMode else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if Task.isCancelled { break }
                await model.loadSessions(silently: true)
            }
        }
    }
}


struct AppSettingsSheet: View {
    @Bindable var model: ConnectionModel
    @Environment(\.dismiss) private var dismiss

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("语言")) {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            LanguageStore.shared.code = language
                        } label: {
                            HStack {
                                Text(language.title())
                                Spacer()
                                if LanguageStore.shared.code == language {
                                    Image(systemName: "checkmark").foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37))
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section(L10n.t("完成提醒")) {
                    Toggle(isOn: Binding(
                        get: { model.completionAlertsEnabled },
                        set: { _ in model.toggleCompletionAlerts() }
                    )) {
                        Text(L10n.t("完成提醒"))
                    }
                }
                Section("DSH Pocket") {
                    HStack {
                        Text(L10n.t("版本"))
                        Spacer()
                        Text(versionText).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.t("设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct ConnectView: View {
    @Bindable var model: ConnectionModel
    @State private var showingScanner = false
    @State private var showingPin = false
    @State private var renamingEndpoint: SavedEndpoint?
    @State private var renameText = ""
    @State private var deletingEndpoint: SavedEndpoint?
    @State private var scanHint: String?

    /// 产品使用说明（飞书文档，已设置"获得链接的人可阅读"）。
    private static let usageDocURL = URL(string: "https://my.feishu.cn/docx/XyhpdKD2Uo5y1ZxXFbscTpizntc")!

    private var card: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    private var pageBackground: Color { Color(uiColor: .systemGroupedBackground) }
    private var brand: Color { Color(red: 0.08, green: 0.48, blue: 0.37) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                if let error = model.errorMessage { errorBanner(error) }
                if let hint = scanHint {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill").foregroundStyle(brand)
                        Text(hint).font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button { scanHint = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                scanConnectCard
                manualSectionTitle
                inputCard
                connectButton
                if !model.savedEndpoints.isEmpty { savedEndpointsCard }
                demoButton
                Text(L10n.t("演示模式使用内置示例数据，不会连接或发送任何内容。"))
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
                QRScannerView { value in
                    if model.useScannedAddress(value) {
                        showingScanner = false
                        // 配对码/认证 URL/PIN 任一命中都直接连接。
                        if !model.pin.isEmpty || model.pendingPairToken != nil || model.pendingLoginToken != nil {
                            scanHint = nil
                            Task { await model.connect() }
                        } else {
                            // 扫的是 dsh-pocket 的「地址型」二维码（方式二）：需要手动输入访问密码。
                            scanHint = L10n.t("已填入地址，请输入电脑上显示的访问密码（方式二）")
                        }
                    }
                }
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
        .alert(L10n.t("删除连接？"), isPresented: Binding(
            get: { deletingEndpoint != nil },
            set: { if !$0 { deletingEndpoint = nil } }
        ), presenting: deletingEndpoint) { endpoint in
            Button(L10n.t("删除"), role: .destructive) {
                model.removeEndpoint(endpoint.address)
                deletingEndpoint = nil
            }
            Button(L10n.t("取消"), role: .cancel) { deletingEndpoint = nil }
        } message: { endpoint in
            Text("\(endpoint.displayName)：\(endpoint.address)")
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
                Text(L10n.t("连接你的 DSH")).font(.headline)
            }
            Spacer(minLength: 8)
            Link(destination: Self.usageDocURL) {
                HStack(spacing: 4) {
                    Image(systemName: "book").font(.caption)
                    Text(L10n.t("使用说明")).font(.footnote.weight(.medium))
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
                Text(L10n.t("已保存的连接"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L10n.t("点按切换"))
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
                        Button {
                            deletingEndpoint = endpoint
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.t("删除连接"))
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

            Text(L10n.t("局域网最多保留 3 个（可命名为「公司」「家」），公网保留最近 1 个；公网地址变化后重新扫码更新。"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 12)
        }
        .background(card, in: RoundedRectangle(cornerRadius: 12))
    }


    /// 扫码连接（主入口）：三步引导 + 大按钮。
    private var scanConnectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(brand)
                Text(L10n.t("扫码连接电脑"))
                    .font(.headline)
                Spacer()
                Text(L10n.t("推荐"))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(brand.opacity(0.12), in: Capsule())
                    .foregroundStyle(brand)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("准备（二选一）"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                prereqRow(
                    icon: "network",
                    title: L10n.t("方式一（推荐）：Tailscale"),
                    detail: L10n.t("电脑装 Tailscale + dsh-pocket-ios 连接器，手机装 Tailscale 和本 App；扫码即连，地址固定")
                )
                prereqRow(
                    icon: "puzzlepiece.extension",
                    title: L10n.t("方式二：dsh-pocket"),
                    detail: L10n.t("电脑装 dsh-pocket 插件（可选再加 dsh-pocket-ios 连接器）；扫它的局域网/公网二维码后输入访问密码")
                )
                Divider().padding(.vertical, 2)
                Text(L10n.t("然后"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                guideStep("1", L10n.t("按你选的路线装好对应插件（方式一：dsh-pocket-ios；方式二：dsh-pocket）"))
                guideStep("2", L10n.t("打开电脑 DSH → 设置 → 手机访问"))
                guideStep("3", L10n.t("扫码：方式一自动连接；方式二输入访问密码"))
            }
            Button {
                showingScanner = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                    Text(L10n.t("扫一扫，连接电脑"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(.white)
                .background(brand, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("scan-connect-button")
        }
        .padding(14)
        .background(card, in: RoundedRectangle(cornerRadius: 14))
    }

    private func prereqRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(brand)
                .frame(width: 22, height: 22)
                .background(brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.footnote.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func guideStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(brand, in: Circle())
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var manualSectionTitle: some View {
        HStack(spacing: 6) {
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
            Text(L10n.t("或手动连接（输入地址与密码）"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
        }
        .padding(.top, 4)
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

            HStack(spacing: 8) {
                Group {
                    if showingPin {
                        TextField(L10n.t("访问密码（扫码连接可跳过）"), text: $model.pin)
                    } else {
                        SecureField(L10n.t("访问密码（扫码连接可跳过）"), text: $model.pin)
                    }
                }
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
                Button {
                    if let pasted = UIPasteboard.general.string {
                        model.pin = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(brand)
                        .frame(width: 32, height: 32)
                        .background(brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("粘贴"))
                Button {
                    showingPin.toggle()
                } label: {
                    Image(systemName: showingPin ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showingPin ? L10n.t("隐藏") : L10n.t("显示"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
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
                Text(model.isConnecting ? L10n.t("正在连接") : L10n.t("连接"))
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
                Text(L10n.t("体验演示模式"))
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
    @State private var showingDisconnectConfirm = false
    @State private var didAutoOpen = false
#if DEBUG
    private var hideDemoBanner: Bool { DebugLaunch.hideDemoBanner }
#else
    private var hideDemoBanner: Bool { false }
#endif

    var body: some View {
        List {
            if model.isDemoMode && !hideDemoBanner {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("演示模式")).font(.footnote.weight(.semibold))
                            Text(L10n.t("示例数据，未连接电脑")).font(.caption).foregroundStyle(.secondary)
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
                ContentUnavailableView(L10n.t("还没有会话"), systemImage: "bubble.left.and.bubble.right", description: Text(L10n.t("创建会话后即可开始对话。")))
                    .listRowSeparator(.hidden)
            }
            ForEach(model.displaySessions) { session in
                let finishedAwaiting = model.finishedAwaitingSessionIds.contains(session.sessionId)
                let isPinned = model.pinnedSessionIds.contains(session.sessionId)
                NavigationLink(value: session) {
                    HStack(spacing: 12) {
                        Image(systemName: session.running ? "ellipsis.bubble.fill" : (finishedAwaiting ? "bell.badge.fill" : "bubble.left"))
                            .foregroundStyle(session.running ? .green : (finishedAwaiting ? .red : .secondary))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Text(session.displayTitle).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                                if isPinned {
                                    Image(systemName: "pin.fill")
                                        .font(.caption2)
                                        .foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37))
                                        .accessibilityLabel(L10n.t("已置顶"))
                                }
                            }
                            Text(finishedAwaiting ? "已完成，等待你的回复"
                                 : (session.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? (session.running ? "正在运行" : "对话记录")))
                                .font(.caption)
                                .foregroundStyle(finishedAwaiting ? Color.red : .secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if session.running {
                            Circle().fill(.green).frame(width: 7, height: 7)
                        } else if finishedAwaiting {
                            Circle().fill(.red).frame(width: 7, height: 7)
                        }
                    }.padding(.vertical, 4)
                }
                .listRowBackground(isPinned ? Color(red: 0.08, green: 0.48, blue: 0.37).opacity(0.05) : Color.clear)
                .contextMenu {
                    Button {
                        Task { await model.togglePin(session) }
                    } label: {
                        Label(model.pinnedSessionIds.contains(session.sessionId) ? L10n.t("取消置顶") : L10n.t("置顶"),
                              systemImage: model.pinnedSessionIds.contains(session.sessionId) ? "pin.slash" : "pin")
                    }
                    Button(role: .destructive) {
                        Task { await model.archive(session) }
                    } label: {
                        Label(L10n.t("归档"), systemImage: "archivebox")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        Task { await model.togglePin(session) }
                    } label: {
                        Label(model.pinnedSessionIds.contains(session.sessionId) ? L10n.t("取消置顶") : L10n.t("置顶"),
                              systemImage: "pin")
                    }
                    .tint(Color(red: 0.08, green: 0.48, blue: 0.37))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await model.archive(session) }
                    } label: {
                        Label(L10n.t("归档"), systemImage: "archivebox")
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay { if model.isLoadingSessions { ProgressView() } }
        .overlay(alignment: .bottom) {
            if model.lastArchivedSession != nil {
                HStack(spacing: 10) {
                    Image(systemName: "archivebox.fill")
                        .foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37))
                    Text(L10n.t("已归档"))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 12)
                    Button(L10n.t("撤销")) { Task { await model.undoArchive() } }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37))
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .refreshable { await model.loadSessions() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if model.isDemoMode {
                    Button { model.exitDemoMode() } label: { Image(systemName: "play.circle.fill") }.accessibilityLabel("退出演示模式")
                } else {
                    Button { showingDisconnectConfirm = true } label: { Image(systemName: "rectangle.portrait.and.arrow.right") }
                        .accessibilityLabel(L10n.t("断开连接"))
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { model.toggleCompletionAlerts() } label: {
                    Image(systemName: model.completionAlertsEnabled ? "bell" : "bell.slash")
                }
                .accessibilityLabel(model.completionAlertsEnabled ? "关闭完成提醒" : "开启完成提醒")
                Button { Task { await model.createSession() } } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("新建会话")
            }
        }
        .navigationTitle(L10n.t("会话"))
        .alert(L10n.t("断开与电脑的连接？"), isPresented: $showingDisconnectConfirm) {
            Button(L10n.t("断开连接"), role: .destructive) { model.disconnect() }
            Button(L10n.t("取消"), role: .cancel) {}
        } message: {
            Text(L10n.t("断开后需要重新扫码配对（或输入访问密码）才能再次连接。"))
        }

        .navigationDestination(for: PocketSession.self) { session in
            ConversationView(model: model, session: session)
                // onAppear 在部分 iOS 版本上不会对同一目的地类型重复触发，
                // 用 task(id:) 确保进入/切换会话时一定重新打开对应会话。
                .task(id: session.sessionId) {
                    model.visibleSessionId = session.sessionId
                    model.open(session)
                }
                .onDisappear {
                    if model.visibleSessionId == session.sessionId {
                        model.visibleSessionId = nil
                    }
                }
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
    // H1 17 / H2 16.5 / H3 16 / H4 15.5 / H5 15 / H6 14.5。移动端与正文接近。
    // 移动端：标题贴近正文大小，避免在气泡里过于抢眼。
    // 注意：Textual 的 fontScale 会叠加在 .gitHub 默认大标题之上（实测 H1 ≈ 1.4 倍正文），
    // 所以这里直接用显式字号覆盖，保证移动端标题与正文接近。
    // fontScale 是乘在 .gitHub 默认标题字号上的（H1≈24pt），因此用 ~0.7 压到正文附近。
    private static let fontScales: [CGFloat] = [0.72, 0.78, 0.84, 0.90, 0.93, 0.96]

    func makeBody(configuration: Configuration) -> some View {
        let index = min(max(configuration.headingLevel - 1, 0), Self.fontScales.count - 1)
        configuration.label
            .textual.fontScale(Self.fontScales[index])
            .fontWeight(.semibold)
            .textual.blockSpacing(.fontScaled(top: 0.8, bottom: 0.3))
    }
}

/// 消息 Markdown 渲染：交给 Textual（MarkdownUI 作者的新库，原生支持跨视图文本选择）。
/// 远程 Markdown 图片（相对 cwd 的本地截图通过 `api/file` 读取）。
struct RemoteMarkdownImage: View {
    let url: URL
    var caption: String? = nil
    @State private var image: UIImage?
    @State private var failed = false
    @State private var showsPreview = false
    private static var cache: [String: UIImage] = [:]

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                HStack(spacing: 6) {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                    Text("图片加载失败").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(width: 200, height: 72)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .tertiarySystemFill))
                    ProgressView()
                }
                .frame(width: 200, height: 120)
            }
        }
        .frame(maxWidth: 240)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { if image != nil { showsPreview = true } }
        .fullScreenCover(isPresented: $showsPreview) {
            if let image { FullscreenImageViewer(image: image) }
        }
        .overlay(alignment: .bottomLeading) {
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                    .padding(6)
            }
        }
        .task {
            guard image == nil else { return }
            if let cached = Self.cache[url.absoluteString] { image = cached; return }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let loaded = UIImage(data: data) else {
                    failed = true
                    return
                }
                Self.cache[url.absoluteString] = loaded
                image = loaded
            } catch {
                failed = true
            }
        }
    }
}

struct MarkdownBody: View {
    let text: String
    var foreground: Color = .primary

    var body: some View {
        StructuredText(markdown: text)
            .textual.textSelection(.enabled)
            // 注意顺序：headingStyle 必须放在 structuredTextStyle 之前（更靠近内容），
            // 否则会被 .gitHub 内置的 headingStyle 覆盖（踩过：改字号完全不生效）。
            .textual.headingStyle(ChatHeadingStyle())
            .textual.structuredTextStyle(.gitHub)
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
    /// 「回到底部」按钮的显示状态：延迟出现，避免发送后程序化滚动期间闪烁并盖住消息。
    @State private var scrollButtonVisible = false
    @State private var scrollButtonTask: Task<Void, Never>?
    /// 是否仍"跟随最新"：用户主动上滑后置 false；回到底部/点箭头后置 true。
    @State private var followsLatest = true
    /// 用户上滑时递增，用于让待执行的补滚任务失效。
    @State private var scrollGeneration = 0
    @State private var didAutoSend = false
    @State private var expandedTurns: Set<Int> = []
    /// 展开/收起「过程」后短时间内抑制"自动贴底"，避免一点击就被拽到底部。
    @State private var suppressAutoScrollUntil = Date.distantPast
    /// 分页加载冷却，避免滚动到顶部时连续翻页。
    @State private var olderCooldownUntil = Date.distantPast
    /// 触发加载时是否已经贴在最顶部：此时加载完直接展示新一页，不做位置锚定。
    @State private var olderLoadWasAtTop = false
    @State private var showingCamera = false
    @State private var photoItems: [PhotosPickerItem] = []
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
            result.append(TimelineEntry(id: group.id, sortKey: group.sequence, sequence: group.sequence, message: nil, group: group))
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

    /// 消息列表的垂直节奏：同人连续 8、换角色 18、过程行相邻 10、turn 切换 24。
    private static func messageSpacing(previous: TimelineEntry, current: TimelineEntry) -> CGFloat {
        if previous.group != nil || current.group != nil { return 10 }
        guard let prevMessage = previous.message, let currentMessage = current.message else { return 10 }
        if prevMessage.isUser != currentMessage.isUser { return 18 }
        return 8
    }

    private var canSend: Bool {
        !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.draftImages.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.conversationError {
                Text(error).font(.footnote).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.red.opacity(0.06))
            }
#if DEBUG
            let showsDemoBanner = model.isDemoMode && !DebugLaunch.hideDemoBanner
#else
            let showsDemoBanner = model.isDemoMode
#endif
            if showsDemoBanner || (!model.isDemoMode && model.liveConnection != .connected) {
                HStack(spacing: 6) {
                    if model.isDemoMode {
                        Image(systemName: "play.circle").font(.caption2).foregroundStyle(.secondary)
                        Text(L10n.t("演示模式 · 示例数据，未连接电脑")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        Circle().fill(Self.liveStateColor(model.liveConnection)).frame(width: 6, height: 6)
                        Text(model.liveConnection.label).font(.caption2).foregroundStyle(.secondary)
                        if model.liveConnection.isDisconnected {
                            Button(L10n.t("重连")) { model.manualReconnect() }
                                .font(.caption2.weight(.semibold))
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal).padding(.vertical, 4)
                .transition(.opacity)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    // 用 VStack 而非 LazyVStack：MarkdownUI/图片/表格行高度动态变化，
                    // LazyVStack 会缓存旧高度导致行重叠；会话窗口只有 30 条消息，直接布局代价可忽略。
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 1).id(Self.topAnchorID)
                        if model.isLoadingOlder {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text(L10n.t("加载更早消息…")).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                        }
                        if model.isLoadingConversation && model.messages.isEmpty && model.steps.isEmpty {
                            ProgressView().padding(.top, 36)
                        }
                        if entries.isEmpty && !model.isLoadingConversation {
                            ContentUnavailableView(L10n.t("开始对话"), systemImage: "text.bubble", description: Text(L10n.t("发送第一条消息。")))
                        }
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            let topGap = index == 0 ? 0 : Self.messageSpacing(previous: entries[index - 1], current: entry)
                            if let message = entry.message {
                                MessageRow(message: message, model: model).id(entry.id).padding(.top, topGap)
                            } else if let group = entry.group {
                                ProcessRow(group: group, expanded: expandedTurns.contains(group.turn), model: model) {
                                    suppressAutoScrollUntil = Date().addingTimeInterval(0.5)
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        if expandedTurns.contains(group.turn) {
                                            expandedTurns.remove(group.turn)
                                        } else {
                                            expandedTurns.insert(group.turn)
                                        }
                                    }
                                }.id(entry.id).padding(.top, topGap)
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
                    // 展开/收起「过程」后的 0.5 秒内不贴底，否则点击会被拽到底部。
                    guard Date() >= suppressAutoScrollUntil else { return }
                    guard isSettlingScroll || followsLatest else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                    }
                }
                .defaultScrollAnchor(.top)
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded {
                    composerFocused = false
                    TextSelectionDismisser.clear()
                })
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            // 用户一旦主动拖动，立刻取消"刚进会话时的多次补滚"，不要跟手指抢滚动。
                            scrollGeneration &+= 1
                            isSettlingScroll = false
                            if value.translation.height > 10 { followsLatest = false }
                        }
                )
                // 视图刚出现时先补滚一次（打开会话的 tick 可能早于 onChange 订阅）。
                .onAppear {
                    isSettlingScroll = true
                    scrollToBottom(proxy: proxy)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { isSettlingScroll = false }
#if DEBUG
                    if DebugLaunch.expandSteps {
                        expandedTurns = Set(model.stepGroups.map(\.turn))
                    }
                    if DebugLaunch.scrollToTop {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            scrollGeneration &+= 1
                            isSettlingScroll = false
                            proxy.scrollTo(Self.topAnchorID, anchor: .top)
                        }
                    }
#endif
                }
                // 打开会话、历史/快照到达：模型递增 tick，视图统一滚到底部。
                .onChange(of: model.focusComposerTick) { _, _ in
            composerFocused = true
        }
#if DEBUG
        .onChange(of: model.stepGroups.count) { _, _ in
            if DebugLaunch.expandSteps {
                expandedTurns = Set(model.stepGroups.map(\.turn))
            }
        }
#endif
        .onChange(of: model.scrollToBottomTick) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: model.messages.count) { oldCount, newCount in
                    timingLog("ui_messages_changed old=\(oldCount) new=\(newCount)")
                    guard newCount != oldCount else { return }
                    if isAtBottom || isSettlingScroll || followsLatest {
                        scrollToBottom(proxy: proxy, force: true)
                    } else if newCount > oldCount {
                        unreadWhileScrolled += newCount - oldCount
                        if unreadWhileScrolled > 5, !scrollButtonVisible {
                            withAnimation(.easeOut(duration: 0.18)) { scrollButtonVisible = true }
                        }
                    }
                }
                .onChange(of: model.steps.count) { oldCount, newCount in
                    guard newCount != oldCount else { return }
                    if isAtBottom || isSettlingScroll || followsLatest { scrollToBottom(proxy: proxy, force: true) }
                }
                .onChange(of: model.olderLoadTick) { _, _ in
                    olderCooldownUntil = Date().addingTimeInterval(1.5)
                    // 已经在最顶部时：让新加载的一页直接出现在顶部（用户继续上滑即可看到更早内容）。
                    // 只有用户停在中间时，才把原来的首条消息锚回顶部，避免内容跳动。
                    if olderLoadWasAtTop {
                        olderLoadWasAtTop = false
                        return
                    }
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
                    olderLoadWasAtTop = topOffset <= 2
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
                        scrollButtonTask?.cancel()
                        scrollButtonVisible = false
                    } else if !followsLatest {
                        // 已在跟随状态下被程序化贴底时，几何短暂变化不打断跟随；只有用户上滑才停。
                        isAtBottom = false
                        isSettlingScroll = false
                    } else if followsLatest {
                        // 内容变高（新消息/过程）但仍在跟随：立即补一次贴底，避免"不自动滚到最新"。
                        scrollToBottom(proxy: proxy, force: true)
                    } else {
                        scrollGeneration &+= 1
                        isAtBottom = false
                    }
                    if !atBottom, !scrollButtonVisible {
                        scrollButtonTask?.cancel()
                        scrollButtonTask = Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.9))
                            guard !Task.isCancelled, !isAtBottom, unreadWhileScrolled > 5 else { return }
                            withAnimation(.easeOut(duration: 0.18)) { scrollButtonVisible = true }
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
#if DEBUG
                    let hideScrollButton = DebugLaunch.hideDemoBanner
#else
                    let hideScrollButton = false
#endif
                    if scrollButtonVisible, unreadWhileScrolled > 5, !entries.isEmpty, !hideScrollButton {
                        Button {
                            unreadWhileScrolled = 0
                            isAtBottom = true
                            followsLatest = true
                            scrollButtonTask?.cancel()
                            scrollButtonVisible = false
                            scrollToBottom(proxy: proxy, force: true)
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .accessibilityLabel(L10n.t("滚到底部"))
                        .accessibilityIdentifier("back-to-bottom")
                        .padding(.trailing, 16)
                        .padding(.bottom, 12)
                    }
                }
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
            if let question = model.pendingQuestion {
                UserQuestionCard(request: question, model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if model.isTurnRunning {
                // 生成状态放在输入栏上方左侧：等待时视线就在这里。
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("\(L10n.t("深度求索中")) · \(elapsed(since: model.turnStartedAt, now: context.date))")
                            .font(.caption)
                            .foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37))
                            .monospacedDigit()
                    }
                    Spacer()
                    Button { Task { await model.cancelTurn() } } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.circle.fill")
                            Text("停止")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("停止生成")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .background(.background)
            }
            Divider()
            inputBar
            }
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
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                // 支持一次多选多张：按选择顺序逐张加载，全部加入草稿后清空选择状态。
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        model.addDraftImage(image)
                    }
                }
                photoItems = []
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
            if let quote = model.pendingQuote {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("引用 \(quote.sender) · #\(quote.sequence)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37))
                        Text(quote.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color(red: 0.08, green: 0.48, blue: 0.37)).frame(width: 3)
                    }
                    Spacer(minLength: 0)
                    Button { model.cancelQuote() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("取消引用")
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
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
                PhotosPicker(selection: $photoItems, maxSelectionCount: 9, selectionBehavior: .ordered, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "photo").font(.system(size: 20))
                        .foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37))
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("从相册选择图片，可多选")
                Button { showingCamera = true } label: {
                    Image(systemName: "camera").font(.system(size: 20))
                        .foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37))
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("拍照")
                TextField(L10n.t("发送消息"), text: $model.draft, axis: .vertical).lineLimit(1...5)
                    .focused($composerFocused)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("composer-field")
                Button {
                    composerFocused = false
                    model.sendMessage(in: session)
                } label: {
                    Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white).frame(width: 44, height: 44)
                        .background(canSend ? Color(red: 0.08, green: 0.48, blue: 0.37) : .gray, in: Circle())
                }.disabled(!canSend).accessibilityLabel("发送消息").accessibilityIdentifier("send-button")
            }.padding(.horizontal).padding(.vertical, 10)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(.background)
    }

    private static let bottomAnchorID = "conversation-bottom-anchor"
    private static let topAnchorID = "conversation-top-anchor"

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
    @State private var copied = false
    /// 只在"复制成功"时递增，避免图标恢复时再触发一次触感。
    @State private var copyHapticTick = 0

    private var hasUserImages: Bool {
        message.isUser && (!message.localImages.isEmpty || !message.images.isEmpty)
    }

    /// 用户消息开头的 Markdown 引用块（`> ` 行）：单独渲染成白色半透明引用卡片，
    /// 否则会套用 Markdown 的深色 blockquote 样式，在绿色气泡上几乎看不见。
    private var leadingQuote: (quote: String, rest: String)? {
        guard message.isUser else { return nil }
        let lines = message.text.components(separatedBy: "\n")
        var quoteLines: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("> ") {
                quoteLines.append(String(line.dropFirst(2)))
                index += 1
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty,
                      !quoteLines.isEmpty,
                      index + 1 < lines.count,
                      lines[index + 1].hasPrefix("> ") {
                index += 1
            } else {
                break
            }
        }
        guard !quoteLines.isEmpty else { return nil }
        let rest = lines[index...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (quoteLines.joined(separator: "\n"), rest)
    }

    /// 气泡内的 Markdown（含原位置插图）。
    @ViewBuilder
    private var markdownContent: some View {
        if message.isUser, let quoted = leadingQuote {
            userQuotedContent(quoted)
        } else {
            plainMarkdownContent
        }
    }

    @ViewBuilder
    private func userQuotedContent(_ quoted: (quote: String, rest: String)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Capsule().fill(Color.white.opacity(0.7)).frame(width: 3)
                Text(quoted.quote)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            if !quoted.rest.isEmpty {
                ForEach(Array(model.markdownSegments(quoted.rest).enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let markdown):
                        MarkdownBody(text: markdown, foreground: .white)
                            .textSelection(.enabled)
                            .tint(Color(red: 0.10, green: 0.35, blue: 0.95))
                    case .image(let url, let caption):
                        RemoteMarkdownImage(url: url, caption: caption)
                    }
                }
            }
        }
        
    }

    @ViewBuilder
    private var plainMarkdownContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(model.markdownSegments(message.text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let markdown):
                    MarkdownBody(text: markdown, foreground: message.isUser ? .white : .primary)
                        .textSelection(.enabled)
                        // 绿色气泡里选区高亮默认取全局绿色 tint → 选中几乎看不出来。
                        // 保持同一绿色色系，用更浅的薄荷绿做选区高亮，和深绿气泡形成明暗对比；
                        // 助手气泡保持默认主题色。
                        .tint(message.isUser ? Color(red: 0.66, green: 0.95, blue: 0.84) : nil)
                case .image(let url, let caption):
                    RemoteMarkdownImage(url: url, caption: caption)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 用户消息的图片缩略图（气泡内左下角，小尺寸）。
    @ViewBuilder
    private var userImageThumbnails: some View {
        HStack(spacing: 6) {
            if !message.localImages.isEmpty {
                ForEach(Array(message.localImages.enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { previewItem = PreviewImageItem(image: image) }
                }
            } else {
                ForEach(message.images) { ref in
                    AttachmentThumbnail(ref: ref, model: model, size: 88)
                }
            }
        }
    }

    private func pendingStateColor(_ state: ConnectionModel.PendingSendState) -> Color {
        if case .failed = state { return Color.red.opacity(0.85) }
        return Color.secondary
    }

    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
            HStack(spacing: 8) {
                if !message.isUser {
                    Image(systemName: "sparkle").foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37))
                }
                Text(message.isUser ? "你" : "DSH").foregroundStyle(.secondary)
                if !message.text.isEmpty {
                    Button {
                        UIPasteboard.general.string = message.text
                        copyHapticTick &+= 1
                        withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            withAnimation(.easeInOut(duration: 0.15)) { copied = false }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(copied ? Color(red: 0.08, green: 0.48, blue: 0.37) : .secondary)
                            .frame(width: 14, height: 14)
                            .scaleEffect(copied ? 1.15 : 1)
                            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: copied)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(copied ? "已复制" : "复制整条消息")
                    .sensoryFeedback(.success, trigger: copyHapticTick)
                    Button {
                        model.beginQuote(message)
                    } label: {
                        Image(systemName: "quote.bubble").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("引用这条消息")
                }
            }.font(.caption2.weight(.semibold))
            HStack {
                if message.isUser { Spacer(minLength: 44) }
                VStack(alignment: .leading, spacing: 8) {
                    if message.isUser, hasUserImages {
                        // 用户发送的图片：作为小缩略图放在气泡内的左下角。
                        VStack(alignment: .leading, spacing: 8) {
                            if !message.text.isEmpty { markdownContent }
                            userImageThumbnails
                        }
                        .padding(.horizontal, 13).padding(.vertical, 10)
                        .background(Color(red: 0.08, green: 0.48, blue: 0.37),
                                    in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .foregroundStyle(.white)
                    } else {
                        // 助手消息里的 attachment 图片仍显示在气泡上方。
                        if !message.isUser, !message.localImages.isEmpty {
                            ForEach(Array(message.localImages.enumerated()), id: \.offset) { _, image in
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: 150, height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .contentShape(Rectangle())
                                    .onTapGesture { previewItem = PreviewImageItem(image: image) }
                            }
                        } else if !message.isUser, !message.images.isEmpty {
                            ForEach(message.images) { ref in
                                AttachmentThumbnail(ref: ref, model: model, size: 150)
                            }
                        }
                        if !message.text.isEmpty {
                            markdownContent
                                
                                .padding(.horizontal, 14).padding(.vertical, 11)
                                .background(message.isUser ? Color(red: 0.08, green: 0.48, blue: 0.37) : Color(red: 0.949, green: 0.949, blue: 0.965), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.primary.opacity(message.isUser ? 0 : 0.05), lineWidth: 0.5)
                                )
                                .foregroundStyle(message.isUser ? .white : .primary)
                        }
                    }
                }
                if !message.isUser { Spacer(minLength: 44) }
            }
            if message.isPending, let state = model.pendingSendState(for: message) {
                HStack(spacing: 5) {
                    switch state {
                    case .sending:
                        ProgressView().scaleEffect(0.55).frame(width: 11, height: 11)
                        Text(L10n.t("发送中…"))
                    case .acked(let steered):
                        Image(systemName: steered ? "arrow.triangle.branch" : "clock").font(.caption2)
                        Text(steered ? L10n.t("已引导，正在继续") : L10n.t("已发出，等待处理"))
                    case .failed:
                        Image(systemName: "exclamationmark.circle").font(.caption2)
                        Text(L10n.t("发送失败"))
                        Button(L10n.t("重新发送")) { model.retryPendingMessage(message) }
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
    @State private var failed = false
    @State private var showsPreview = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .tertiarySystemFill))
                    VStack(spacing: 4) {
                        Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                        Text("图片加载失败").font(.caption2).foregroundStyle(.secondary)
                    }
                }
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
        .task {
            if image == nil {
                image = await model.loadImage(ref)
                if image == nil { failed = true }
            }
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 最后一条未完成的步骤 = 当前正在执行的动作。
    private var runningStep: PocketStep? {
        group.steps.last(where: { !$0.finished })
    }

    private var summary: String {
        if let runningStep {
            return "\(runningStep.runningLabel) · \(group.steps.count) 步"
        }
        var seen = Set<String>()
        var labels: [String] = []
        for step in group.steps where !seen.contains(step.label) {
            seen.insert(step.label)
            labels.append(step.label)
        }
        let joined = labels.prefix(3).joined(separator: "、")
        return "过程 · \(group.steps.count) 步 · \(joined)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 16, height: 16)
                    Text(summary).font(.footnote).lineLimit(1)
                        .foregroundStyle(runningStep == nil ? .secondary : Color(red: 0.08, green: 0.48, blue: 0.37))
                    if runningStep != nil {
                        ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(group.steps) { step in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .top, spacing: 8) {
                                Group {
                                    if step.finished {
                                        Image(systemName: step.icon).font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        ProgressView().scaleEffect(0.55)
                                    }
                                }.frame(width: 16)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(step.finished ? step.label : step.runningLabel)
                                        .font(.footnote)
                                        .foregroundStyle(step.finished ? .primary : Color(red: 0.08, green: 0.48, blue: 0.37))
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
                // 从摘要行下方"向下展开"：只用淡入 + 顶部锚点微缩放，
                // 不要用 .move(edge: .top)，否则文字会从上一行上方滑下来。
                .padding(.top, 4)
                .padding(.horizontal, 12)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                .clipped()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: expanded)
        .padding(.vertical, 12)
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

// MARK: - UIKit 消息列表（实验分支：彻底解决长历史滚动/复用）

/// 会话列表项（消息或过程组），供 UIKit 列表与 SwiftUI 列表共用。
