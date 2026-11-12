import Foundation

/// 消息列表的垂直节奏与未读计数。
///
/// 抽出来的原因：这两个规则决定「同一个人连着说的话看起来是不是一伙的」，
/// 也和「离开底部后到底有几条新回复」直接相关——都是可判定的，不该写在视图里靠肉眼调。
public enum TimelineSpacing {
    /// 同人连续 8、换角色 18、过程行/失败卡相邻 10。
    public static func between(previousIsGroup: Bool, currentIsGroup: Bool,
                               previousIsUser: Bool?, currentIsUser: Bool?) -> Int {
        if previousIsGroup || currentIsGroup { return 10 }
        guard let previousIsUser, let currentIsUser else { return 10 }
        return previousIsUser == currentIsUser ? 8 : 18
    }

    public static let groupSpacing = 10
    public static let sameSpeakerSpacing = 8
    public static let speakerChangeSpacing = 18
}

public enum UnreadCounter {
    /// 离开底部之后到达的**助手回复**条数：用户自己的消息和仍在待发的都不算。
    public static func replies(after mark: Int,
                               messages: [(isUser: Bool, isPending: Bool, sequence: Int)]) -> Int {
        messages.filter { !$0.isUser && !$0.isPending && $0.sequence > mark }.count
    }
}
