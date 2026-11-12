import Foundation

/// 发送前的网络预判：已知不可达就别白等重试。
///
/// 为什么需要：`performSend` 原先走「先试 → 失败 → 分型」，重试 3 次（退避 800/2000/3000ms）
/// 且每次可能等 TCP 超时 20 秒。用户实测断网到「写入暂存」隔了 18 秒，界面一直显示「发送中」。
/// 而 `NWPathMonitor` 当时就知道不可达——只是没把状态暴露给发送路径。
public enum SendPreflightAction: Equatable, Sendable {
    /// 直接发送（可达，或状态未知）。
    case send
    /// 已知不可达：直接写入断网暂存，跳过重试。
    case holdOffline
}

public enum SendPreflightPolicy {
    /// - Parameter isReachable: `nil` 表示尚未探测到网络状态（App 冷启动头几秒）。
    ///
    /// **「不知道」必须等同于「可以试」**：若把 nil 当成不可达，冷启动时发的消息会被错误暂存，
    /// 用户会看到「现在断网」但其实网络是好的。这是本策略最容易写错的边界。
    public static func action(isReachable: Bool?) -> SendPreflightAction {
        isReachable == false ? .holdOffline : .send
    }
}
