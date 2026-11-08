import Foundation

/// 滚动策略（模块 04）：followsLatest —— 在底部才自动跟随，否则累计未读并显示"回到底部"。
public enum ScrollAction: Equatable, Sendable {
    case autoScroll
    case keepPosition
}

public struct ScrollPolicy: Equatable, Sendable {
    public private(set) var isAtBottom: Bool
    public private(set) var isSettling: Bool
    public private(set) var unreadCount: Int
    public private(set) var generation: Int

    public init(isAtBottom: Bool = true, isSettling: Bool = false) {
        self.isAtBottom = isAtBottom
        self.isSettling = isSettling
        self.unreadCount = 0
        self.generation = 0
    }

    public var showsBackToBottom: Bool { !isAtBottom }

    public mutating func beginSettling() { isSettling = true }
    public mutating func endSettling() { isSettling = false }

    /// 用户滚动：离开底部会递增 generation，使待执行的补滚任务失效。
    public mutating func onScrollChanged(isAtBottom nowAtBottom: Bool) {
        if !nowAtBottom { generation &+= 1 }
        isAtBottom = nowAtBottom
        if nowAtBottom { unreadCount = 0 }
    }

    /// 新消息到达：在底部/首屏稳定期自动跟随，否则只累计未读。
    public mutating func onNewMessages(delta: Int) -> ScrollAction {
        guard delta > 0 else { return .keepPosition }
        if isAtBottom || isSettling {
            return .autoScroll
        }
        unreadCount += delta
        return .keepPosition
    }

    /// 是否允许执行滚动（force = 用户点"回到底部"）。
    public mutating func requestBottom(force: Bool = false) -> Bool {
        if force {
            unreadCount = 0
            isAtBottom = true
            return true
        }
        return isAtBottom || isSettling
    }

    /// 到达底部回调。
    public mutating func reachedBottom() {
        isAtBottom = true
        unreadCount = 0
    }
}

/// 输入栏策略（模块 04）。
public enum ComposerButton: Equatable, Sendable {
    case send
    case cancel
}

public struct ComposerPolicy: Equatable, Sendable {
    public var text: String
    public var imageCount: Int
    public var isSending: Bool

    public init(text: String = "", imageCount: Int = 0, isSending: Bool = false) {
        self.text = text
        self.imageCount = imageCount
        self.isSending = isSending
    }

    public var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var canSend: Bool { (trimmedText.isEmpty == false || imageCount > 0) && !isSending }
    public var button: ComposerButton { isSending ? .cancel : .send }

    /// 输入在任何状态下都允许（生成中可继续输入/追加）。
    public var allowsTyping: Bool { true }
}

/// 发送状态展示（模块 04）。
public struct PendingPresentation: Equatable, Sendable {
    public let label: String
    public let isFailed: Bool
    public let isRetryable: Bool
}

public enum PendingPresentationBuilder {
    public static func make(state: MessageSendState) -> PendingPresentation {
        switch state {
        case .sending:
            return PendingPresentation(label: "发送中…", isFailed: false, isRetryable: false)
        case .accepted(.steer):
            return PendingPresentation(label: "已引导，正在继续", isFailed: false, isRetryable: false)
        case .accepted(.queue):
            return PendingPresentation(label: "已发出，等待处理", isFailed: false, isRetryable: false)
        case .failed:
            return PendingPresentation(label: "发送失败", isFailed: true, isRetryable: true)
        case .committed:
            return PendingPresentation(label: "", isFailed: false, isRetryable: false)
        }
    }
}

/// 连接状态展示（模块 04）。
public enum ConnectionStatusKind: Equatable, Sendable {
    case connected
    case connecting
    case reconnecting
    case disconnected
    case idle
}

public struct ConnectionStatusPresentation: Equatable, Sendable {
    public let label: String
    public let kind: ConnectionStatusKind
    public let showsRetry: Bool
}

public enum ConnectionStatusBuilder {
    public static func make(state: SyncConnectionState) -> ConnectionStatusPresentation {
        switch state {
        case .connected:
            return .init(label: "已连接", kind: .connected, showsRetry: false)
        case .connecting:
            return .init(label: "正在连接", kind: .connecting, showsRetry: false)
        case .reconnecting(let attempt):
            let label = attempt > 1 ? "重连中（第 \(attempt) 次）" : "正在重连"
            return .init(label: label, kind: .reconnecting, showsRetry: false)
        case .disconnected:
            return .init(label: "已断开", kind: .disconnected, showsRetry: true)
        case .idle:
            return .init(label: "未连接", kind: .idle, showsRetry: false)
        }
    }
}

/// 复制整条消息（模块 04）。
public enum CopyTextBuilder {
    public static func wholeMessage(_ text: String) -> String {
        text.trimmingCharacters(in: .newlines)
    }
}
