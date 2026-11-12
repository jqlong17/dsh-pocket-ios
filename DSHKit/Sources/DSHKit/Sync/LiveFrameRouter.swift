import Foundation

/// 实时流一帧数据属于哪一类。
///
/// 抽出来的原因：acceptLive 里靠嵌套的 if/else 判断「是快照、是消息、是 steer 收件箱、还是过程事件」，
/// 四种形态的判定条件都不直观（尤其 steer 的 `inserted[].source.rpcId`），
/// 写错就会静默丢消息或误报失败。判定放这里之后可以直接测。
public enum LiveFrameKind: Equatable, Sendable {
    /// 历史快照（首帧）。
    case snapshot
    /// 一条可解析为用户/助手消息的事件。
    case message
    /// steer 插入收件箱的事件（消息还没变成 user/message，但已送达）。
    case steerInbox
    /// 其它过程事件（工具步骤、turn 起止等）。
    case event
    /// 认不出的帧。
    case unknown
}

public enum LiveFrameRouter {
    public static func kind(of value: [String: Any]) -> LiveFrameKind {
        if value["type"] as? String == "snapshot" { return .snapshot }
        guard let event = value["event"] as? [String: Any] else { return .unknown }
        if event["type"] as? String == "agent/inbox/spliced" { return .steerInbox }
        // 有 message 形态的 data 才算消息；否则按过程事件处理（由调用方再解析）。
        if let data = event["data"] as? [String: Any], data["message"] != nil || data["kind"] != nil {
            return .message
        }
        return .event
    }

    /// 从 steer 收件箱事件里取出 rpcId 集合（小写）。
    public static func steerInboxRpcIds(from event: [String: Any]) -> Set<String> {
        guard event["type"] as? String == "agent/inbox/spliced",
              let data = event["data"] as? [String: Any],
              let inserted = data["inserted"] as? [[String: Any]] else { return [] }
        return Set(inserted.compactMap {
            ($0["source"] as? [String: Any])?["rpcId"] as? String
        }.map { $0.lowercased() })
    }

    /// 认不出的帧，取出 type 与 source.kind 便于写诊断。
    public static func describe(_ value: [String: Any]) -> (type: String, sourceKind: String?) {
        let event = value["event"] as? [String: Any]
        let data = event?["data"] as? [String: Any]
        return (event?["type"] as? String ?? "未知",
                (data?["source"] as? [String: Any])?["kind"] as? String)
    }
}
