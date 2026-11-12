import Foundation

/// `workspace/follow` 的首帧基线：哪些会话已归档、哪些被置顶。
///
/// 抽成纯解析：帧结构判断（streamId / type=item / value.type=baseline）容易写错，
/// 放在 App 的 socket 循环里既无法测试，也让那个循环又长又难读。
public enum WorkspaceBaseline {
    public struct Decoded: Equatable, Sendable {
        public let archived: Set<String>
        public let pinned: [String]
        public init(archived: Set<String>, pinned: [String]) {
            self.archived = archived
            self.pinned = pinned
        }
    }

    public enum Result: Equatable, Sendable {
        /// 不是本流的帧或不关心，跳过继续读。
        case skip
        /// 收到基线。
        case baseline(Decoded)
        /// 是本流基线但结构不对，应当报错（而不是静默继续等）。
        case malformed
    }

    public static func decode(frame: Data, streamId: String) -> Result {
        guard let envelope = try? JSONSerialization.jsonObject(with: frame) as? [String: Any],
              envelope["streamId"] as? String == streamId,
              envelope["type"] as? String == "item",
              let value = envelope["value"] as? [String: Any] else { return .skip }
        guard value["type"] as? String == "baseline" else { return .skip }
        guard let baseline = value["value"] as? [String: Any],
              let archived = baseline["archivedSessionIds"] as? [String] else { return .malformed }
        let pinned = baseline["pinnedSessionIds"] as? [String] ?? []
        return .baseline(Decoded(archived: Set(archived), pinned: pinned))
    }
}
