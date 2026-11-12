import Foundation

/// 在历史记录里找「这条消息到底有没有落库」。
///
/// 两种落库形态都要认：
/// 1. `user/message` 且 `source.rpcId` 匹配（正常路径）；
/// 2. `agent/inbox/spliced` 里的 `inserted[].source.rpcId`（生成中被 steer 插进 inbox，
///    不会立刻变成 user/message，但确实已送达）。
/// 第二条容易漏，漏了就会把「已送达」误判成「服务端没收到」，让用户重复发送。
public enum SendLandedScan {
    public static func landed(inRecords records: [[String: Any]], requestId: String) -> Bool {
        for record in records {
            guard let event = record["event"] as? [String: Any],
                  let data = event["data"] as? [String: Any] else { continue }
            let type = event["type"] as? String

            if type == "user/message",
               let source = data["source"] as? [String: Any],
               let rpcId = source["rpcId"] as? String,
               RPCId.matches(rpcId, requestId) {
                return true
            }

            if type == "agent/inbox/spliced",
               let inserted = data["inserted"] as? [[String: Any]] {
                for item in inserted {
                    guard let source = item["source"] as? [String: Any],
                          let rpcId = source["rpcId"] as? String else { continue }
                    if RPCId.matches(rpcId, requestId) { return true }
                }
            }
        }
        return false
    }
}
