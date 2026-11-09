/// 检测会话"运行中 → 已结束"的转换，用于完成提醒（红点 / 通知）。
///
/// 只根据 `session/list` 的 `running` 布尔值做状态机比较：
/// - 上一轮为 true、这一轮为 false → 记一次完成；
/// - 首次看到某个会话（没有历史状态）不算完成，避免启动时误提醒。
public struct SessionCompletionTracker: Equatable {
    /// 最近一次观察到的 running 状态。
    public private(set) var running: [String: Bool]

    public init(previous: [String: Bool] = [:]) {
        self.running = previous
    }

    /// 用最新一轮 `session/list` 的 running 状态更新，返回**本次新完成**的会话 id。
    /// @param latest - sessionId → running。
    /// @returns 从运行中变为已结束的会话 id（按输入顺序去重）。
    public mutating func update(latest: [String: Bool]) -> [String] {
        var completed: [String] = []
        for (sessionId, isRunning) in latest {
            if running[sessionId] == true, !isRunning {
                completed.append(sessionId)
            }
        }
        running = latest
        return completed
    }

    /// 某个会话重新开始运行（例如用户又发了消息），不再算"已完成"。
    public func isRunning(_ sessionId: String) -> Bool {
        running[sessionId] == true
    }
}
