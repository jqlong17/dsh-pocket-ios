import Foundation

/// 输入区要不要再显示「需要你确认」。
///
/// 电脑上已经答过，或提出这个问题的那一轮已经结束，卡片就不该再占着。
public enum PendingQuestionPolicy {
    public static func shouldShow(hasResult: Bool, turnEnded: Bool) -> Bool {
        !hasResult && !turnEnded
    }
}
