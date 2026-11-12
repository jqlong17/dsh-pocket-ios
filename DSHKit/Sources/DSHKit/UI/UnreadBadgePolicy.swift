import Foundation

/// 「回到底部」入口什么时候出现、角标写什么。
///
/// 只数**助手已经答完的消息**：用户自己发的不算，还在路上的不算。
/// 否则连着发几句话就会被当成一堆未读。
public enum UnreadBadgePolicy {
    /// 攒够几条助手回复再出现入口。
    public static let replyThreshold = 5

    public static func shouldShowBadge(assistantReplies: Int) -> Bool {
        assistantReplies >= replyThreshold
    }

    /// 角标文案。0 条不显示，超过 99 显示 `99+`。
    public static func badgeText(for assistantReplies: Int) -> String? {
        guard assistantReplies > 0 else { return nil }
        return assistantReplies > 99 ? "99+" : "\(assistantReplies)"
    }
}
