import Foundation

/// `$events` 通道：服务端把需要客户端处理的请求推过来，客户端处理后回传结果。
///
/// 为什么需要它：`ask_user_question` 的问答卡如果走 `userQuestions/answer`，
/// 服务端要求问题处于 `continued` 状态——而该状态只在工具超时（默认 120 秒）后出现。
/// 浏览器端不是这么做的：它打开 `$events` 流，收到请求后**直接把答案作为请求结果回传**，
/// 所以点完立即生效。这个类型就是那套协议的解析层。
///
/// 协议来源（DSH 0.2.2-rc.2）：
/// - `dsh-api-gateway/lib/types/stream-protocol.js`（常量）
/// - `dsh-api-gateway/lib/client.browser.js`（处理流程）
public enum RemoteEventProtocol {
    /// 与 `session/follow` 共用 `/api/remote.mux`，只是 endpoint 不同。
    public static let streamEndpoint = "$events"
    /// 回传处理结果用的 HTTP RPC 方法名。
    public static let resultEndpoint = "$events/result"
    /// 开流时发送的空参数。
    public static let streamPayload: [String: Any] = ["args": [String: Any]()]

    /// 开流后服务端下发的第一帧：证明事件源就绪，并给出本次会话的 clientId。
    public struct Ready: Equatable {
        public let clientId: String
        public let host: String?

        public init(clientId: String, host: String?) {
            self.clientId = clientId
            self.host = host
        }
    }

    /// 后续帧的分类。
    ///
    /// 手写 `==`：`.request` 里带着原始字典（`[String: Any]` 没有 Equatable），
    /// 测试只需要按「类型 + eventId」判断相等。
    public enum Frame: Equatable {
        /// 服务端撤销了这个请求，客户端应停止处理。
        case cancel(eventId: String)
        /// 单向事件通知，不需要回传结果。
        case emit(eventId: String)
        /// 需要客户端处理并回传结果的请求。`raw` 保留整帧，字段名在实测后确认。
        case request(eventId: String, raw: [String: Any])
        /// 认不出的帧。调用方应记录日志后忽略。
        case unknown(type: String?)

        public static func == (lhs: Frame, rhs: Frame) -> Bool {
            switch (lhs, rhs) {
            case (.cancel(let a), .cancel(let b)): return a == b
            case (.emit(let a), .emit(let b)): return a == b
            case (.request(let a, _), .request(let b, _)): return a == b
            case (.unknown(let a), .unknown(let b)): return a == b
            default: return false
            }
        }
    }

    /// 解析就绪帧。缺 `clientId` 视为未就绪（返回 nil，调用方继续等）。
    ///
    /// `host` 在实测帧里是对象（`{"home":"/Users/<user>"}`），不是字符串，
    /// 所以这里宽松取值：字符串直接用，对象取 `home`，都不是就为 nil。
    public static func ready(from value: [String: Any]) -> Ready? {
        guard value["type"] as? String == "ready",
              let clientId = value["clientId"] as? String,
              !clientId.isEmpty else { return nil }
        let host: String?
        if let text = value["host"] as? String {
            host = text
        } else if let object = value["host"] as? [String: Any] {
            host = object["home"] as? String
        } else {
            host = nil
        }
        return Ready(clientId: clientId, host: host)
    }

    /// 分类一帧。判断顺序与浏览器端一致：先看 `type`，再看有没有 `eventId`。
    public static func frame(from value: [String: Any]) -> Frame {
        let type = value["type"] as? String
        let eventId = value["eventId"] as? String
        switch type {
        case "cancel":
            guard let eventId, !eventId.isEmpty else { return .unknown(type: type) }
            return .cancel(eventId: eventId)
        case "emit":
            guard let eventId, !eventId.isEmpty else { return .unknown(type: type) }
            return .emit(eventId: eventId)
        default:
            guard let eventId, !eventId.isEmpty else { return .unknown(type: type) }
            return .request(eventId: eventId, raw: value)
        }
    }

    /// 成功回传体：`{ clientId, eventId, outcome: { kind: "result", value } }`。
    public static func resultBody(clientId: String, eventId: String, value: Any?) -> [String: Any] {
        var outcome: [String: Any] = ["kind": "result"]
        if let value { outcome["value"] = value }
        return ["clientId": clientId, "eventId": eventId, "outcome": outcome]
    }

    /// 拒绝回传体：`{ clientId, eventId, outcome: { kind: "rejected", error: { name, message } } }`。
    ///
    /// 必须回传——服务端在等这个结果，不回传会让那条 waterfall 一直挂着。
    public static func rejectionBody(clientId: String, eventId: String, message: String) -> [String: Any] {
        [
            "clientId": clientId,
            "eventId": eventId,
            "outcome": [
                "kind": "rejected",
                "error": ["name": "Error", "message": message]
            ]
        ]
    }

    /// 从请求帧里取方法名。
    ///
    /// 帧的字段名在实测前不确定（浏览器端 compression 后看不出），所以这里按几个
    /// 常见位置依次尝试。实测确认后可收敛到单一路径。
    public static func methodName(in raw: [String: Any]) -> String? {
        if let method = raw["method"] as? String { return method }
        if let endpoint = raw["endpoint"] as? String { return endpoint }
        if let payload = raw["payload"] as? [String: Any] {
            if let method = payload["method"] as? String { return method }
            if let endpoint = payload["endpoint"] as? String { return endpoint }
        }
        // 兜底：整帧里找已知的问答方法名
        let text = String(describing: raw)
        if text.contains("user-questions/request") { return "user-questions/request" }
        return nil
    }

    /// 从请求帧里取参数对象。
    public static func arguments(in raw: [String: Any]) -> [String: Any]? {
        if let args = raw["args"] as? [String: Any] { return args }
        if let payload = raw["payload"] as? [String: Any] {
            if let args = payload["args"] as? [String: Any] { return args }
            return payload
        }
        return nil
    }
}
