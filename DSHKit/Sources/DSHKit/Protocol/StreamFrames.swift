import Foundation

/// 实时流帧的编码/过滤（用例 P04–P05）。
public enum StreamFrames {
    public static let remoteMuxPath = "api/remote.mux"

    /// `session/follow` 的 open 帧。
    public static func openFrame(streamId: String, sessionId: String, maxMessages: Int) -> [String: Any] {
        [
            "type": "open",
            "streamId": streamId,
            "endpoint": "session/follow",
            "payload": [
                "args": [
                    "request": [
                        "address": ["kind": "session", "sessionId": sessionId],
                        "maxMessages": maxMessages
                    ]
                ]
            ]
        ]
    }

    /// 只接受匹配 streamId 且 type=item 的帧。
    public static func isItemFrame(_ json: [String: Any], streamId: String) -> Bool {
        json["type"] as? String == "item" && json["streamId"] as? String == streamId
    }
}
