import Foundation

/// VoiceOver 朗读用的句子。
///
/// 复合行（过程、任务、消息）不要逐个碎片朗读，拼成一句完整的话；
/// 句子怎么拼是纯逻辑，放这里可测，视图只负责挂上去。
public enum AccessibilityLabels {
    /// 过程行：**过程，4 步：执行了命令、写入了文件**；运行中加一句正在做什么。
    public static func processGroup(stepLabels: [String], runningLabel: String?) -> String {
        let steps = stepLabels.count
        if let runningLabel, !runningLabel.isEmpty {
            return steps == 0 ? runningLabel : "\(runningLabel)，共 \(steps) 步"
        }
        guard steps > 0 else { return "过程，没有步骤" }
        let distinct = Array(NSOrderedSet(array: stepLabels)) as? [String] ?? stepLabels
        let shown = distinct.prefix(3).joined(separator: "、")
        let more = distinct.count > 3 ? "等" : ""
        return "过程，\(steps) 步：\(shown)\(more)"
    }

    /// 后台任务行：**跑测试，正在运行，已跑 12 秒**。
    public static func job(name: String, statusLabel: String, elapsed: String?) -> String {
        var parts = [name, statusLabel]
        if let elapsed, !elapsed.isEmpty { parts.append("已跑 \(elapsed)") }
        return parts.joined(separator: "，")
    }

    /// 回到底部：**回到底部，5 条新回复**。
    public static func backToBottom(unreadReplies: Int) -> String {
        guard let badge = UnreadBadgePolicy.badgeText(for: unreadReplies) else { return "回到底部" }
        return "回到底部，\(badge) 条新回复"
    }

    /// 图片：**图片 2，共 3 张，双击查看大图**。
    public static func attachment(index: Int?, total: Int?) -> String {
        guard let index, let total, total > 1 else { return "图片，双击查看大图" }
        return "图片 \(index)，共 \(total) 张，双击查看大图"
    }

    /// 消息气泡：读之前先说清是谁说的。正文由系统继续朗读。
    public static func messageSender(isUser: Bool) -> String {
        isUser ? "你" : "DSH"
    }

    /// 会话列表行：**做一个 iOS 版 DSH，正在运行**；置顶要明说。
    public static func sessionRow(title: String, status: String, isPinned: Bool) -> String {
        var parts = [title, status]
        if isPinned { parts.append("已置顶") }
        return parts.joined(separator: "，")
    }

    /// 新回复播报：**DSH 回复了，5 条未读**。读屏用户看不到屏幕，靠这句知道有新内容。
    public static func newReplyAnnouncement(unreadReplies: Int) -> String {
        guard unreadReplies > 0 else { return "DSH 回复了" }
        return "DSH 回复了，\(unreadReplies) 条未读"
    }
}
