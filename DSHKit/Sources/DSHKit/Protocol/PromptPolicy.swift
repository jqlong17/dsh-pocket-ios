import Foundation

/// 发送模式：决定这条消息是「新开一轮」还是「插进当前轮」。
///
/// 为什么统一：这行三元表达式原先散在三处（发送、通知回复、断网补发），
/// 三处的判定条件已经不一致——补发要固定 queue，实时发送要「确认过 turn 事件」。
/// 收敛成一处之后，规则可以直接测，也不会再各写各的。
public enum PromptMode: String, Equatable, Sendable {
    case queue
    case steer
}

public enum PromptPolicy {
    /// 实时发送：**在跑就打断**。
    ///
    /// 曾经要求「见过实时 turn 事件」才 steer，结果生成中发的消息全被排到当前轮之后，
    /// 电脑端显示「排队」——用户以为消息卡住了。排队带来的体感损失远大于误打断：
    /// 误打断最多让 AI 多问一句，排队则要等整轮跑完。
    /// `isRunning` 本身已由 turn 事件驱动（列表状态只用于首帧），足够可信。
    public static func liveMode(isRunning: Bool) -> PromptMode {
        isRunning ? .steer : .queue
    }

    /// 通知/手表回复：列表里的 running 可能滞后，统一排队，避免误打断。
    public static func replyMode(isRunning: Bool) -> PromptMode {
        .queue
    }

    /// 断网补发：积压是「排着说」，一律排队（见 OfflineDeliveryPolicy）。
    public static var backlogMode: PromptMode { .queue }
}
