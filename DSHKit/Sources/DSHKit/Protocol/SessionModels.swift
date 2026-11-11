import Foundation

/// 会话（用例 P30–P33）。
public struct DSHSession: Identifiable, Hashable, Sendable {
    public let sessionId: String
    public let updatedAt: Double
    public let running: Bool
    public let blank: Bool
    public let title: String?
    public let cwd: String?
    public let origin: String?
    public let parentSessionId: String?

    public var id: String { sessionId }

    public var isSubagent: Bool { origin == "subagent" || parentSessionId != nil }

    /// 对齐 DSH 桌面侧边栏：隐藏归档（外部过滤）、subagent、空会话。
    public var isVisibleInList: Bool {
        guard !isSubagent, !blank else { return false }
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return true
    }

    /// 列表可见性：排除归档 id、subagent、空会话。
    public static func visible(in sessions: [DSHSession], archivedSessionIds: Set<String>) -> [DSHSession] {
        sessions.filter { !archivedSessionIds.contains($0.sessionId) && $0.isVisibleInList }
    }

    public init(sessionId: String, updatedAt: Double, running: Bool, blank: Bool,
                title: String? = nil, cwd: String? = nil,
                origin: String? = nil, parentSessionId: String? = nil) {
        self.sessionId = sessionId
        self.updatedAt = updatedAt
        self.running = running
        self.blank = blank
        self.title = title
        self.cwd = cwd
        self.origin = origin
        self.parentSessionId = parentSessionId
    }
}

public struct DSHImageRef: Hashable, Sendable {
    public let attachmentId: String
    public let mediaType: String?
    public let bytes: Int?
    public let width: Int?
    public let height: Int?
    public let name: String?

    public init(attachmentId: String, mediaType: String? = nil, bytes: Int? = nil,
                width: Int? = nil, height: Int? = nil, name: String? = nil) {
        self.attachmentId = attachmentId
        self.mediaType = mediaType
        self.bytes = bytes
        self.width = width
        self.height = height
        self.name = name
    }
}

/// 一条聊天消息（用例 P20–P22、P26）。
public struct DSHMessage: Identifiable, Equatable, Sendable {
    public let id: String
    public let sequence: Int
    public let kind: String
    public let text: String
    public let isUser: Bool
    public let rpcId: String?
    public let images: [DSHImageRef]

    public init(id: String, sequence: Int, kind: String, text: String,
                isUser: Bool, rpcId: String? = nil, images: [DSHImageRef] = []) {
        self.id = id
        self.sequence = sequence
        self.kind = kind
        self.text = text
        self.isUser = isUser
        self.rpcId = rpcId
        self.images = images
    }
}

/// `turn/end` 的失败原因。成功结束时为 nil。
public struct DSHTurnFailure: Equatable, Sendable {
    public let message: String
    public let code: String?

    public init(message: String, code: String?) {
        self.message = message
        self.code = code
    }
}

/// 工具过程事件（用例 P23–P24）。
public enum DSHStepEvent: Equatable, Sendable {
    case toolCall(seq: Int, turn: Int, callId: String, name: String, detail: String, arguments: String)
    case toolResult(seq: Int, turn: Int, callId: String, text: String, isError: Bool, images: [DSHImageRef])
    case turnStart(seq: Int, turn: Int)
    case turnEnd(seq: Int, turn: Int, failure: DSHTurnFailure?)
}

/// 历史分页（用例 P40）。
public struct DSHSessionPage: Sendable {
    public let records: [DSHRecord]
    public let hasMore: Bool

    public init(records: [DSHRecord], hasMore: Bool) {
        self.records = records
        self.hasMore = hasMore
    }
}

public enum DSHRecord: Sendable {
    case message(DSHMessage)
    case step(DSHStepEvent)
    case title(seq: Int, title: String)
    case unknown
}

/// 实时 assistant 增量帧（用例 P25）。
public enum DSHStreamFrame: Equatable, Sendable {
    case start(attemptId: String, turn: Int, step: Int)
    case textDelta(attemptId: String, index: Int, text: String)
    case end(attemptId: String, outcome: String?)
    case other
}
