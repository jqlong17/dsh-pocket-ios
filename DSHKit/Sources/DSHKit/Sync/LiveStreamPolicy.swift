import Foundation

/// 实时流的时序参数与假死判定。
///
/// 为什么要集中：这些数字散在 follow 循环里，改一个要读 130 行；
/// 而且「生成中 25 秒无帧就主动重连」是踩过的坑（公网隧道会假死），
/// 写在循环里无法测试，也就无法防止有人顺手把它调成 60 秒。
public enum LiveStreamPolicy {
    /// 心跳间隔：定期 ping，避免中间层回收空闲连接。
    public static let heartbeatInterval: Duration = .seconds(25)
    /// 生成中允许的最长静默：超过即认定假死，主动断开重连。
    public static let runningIdleTimeout: Duration = .seconds(25)
    /// 重连退避：从 1 秒开始翻倍，上限 20 秒。
    public static let initialReconnectDelay: Duration = .seconds(1)
    public static let maxReconnectDelay: Duration = .seconds(20)
    /// 断流兜底轮询：最多 30 次、每次间隔 500 毫秒（约 15 秒）。
    public static let historyPollAttempts = 30
    public static let historyPollInterval: Duration = .milliseconds(500)

    /// 下一次重连等待多久。
    public static func nextReconnectDelay(after current: Duration) -> Duration {
        let doubled = current * 2
        return doubled > maxReconnectDelay ? maxReconnectDelay : doubled
    }

    /// 只有「生成中」才需要静默检测：空闲时长时间没帧是正常的。
    public static func shouldReconnect(isRunning: Bool, idle: Duration) -> Bool {
        isRunning && idle >= runningIdleTimeout
    }
}
