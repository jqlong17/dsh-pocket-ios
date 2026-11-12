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
    /// 实时发送：只有**确认过实时 turn 事件且确实在跑**才打断；
    /// 否则排队——queue 最多晚一轮，steer 会打断正在做的事。
    public static func liveMode(turnEventsSeen: Bool, isRunning: Bool) -> PromptMode {
        (turnEventsSeen && isRunning) ? .steer : .queue
    }

    /// 通知/手表回复：列表里的 running 可能滞后，统一排队，避免误打断。
    public static func replyMode(isRunning: Bool) -> PromptMode {
        .queue
    }

    /// 断网补发：积压是「排着说」，一律排队（见 OfflineDeliveryPolicy）。
    public static var backlogMode: PromptMode { .queue }
}
