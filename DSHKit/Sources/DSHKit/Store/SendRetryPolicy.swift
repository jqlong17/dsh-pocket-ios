import Foundation

/// 连接恢复后，哪些未送达条目值得自动补发一次。
///
/// 两类未送达的处理不同：
/// - `heldOffline`（断网暂存）：每次联网都该补发，直到成功；
/// - `sendFailed`（其它失败）：**只自动补发一次**，避免永久失败的消息被反复重试。
/// 用户手点「重新发送」会清掉 `autoRetried`，等于再给它一次机会。
public enum SendRetryPolicy {
    public static func shouldAutoResend(heldOffline: Bool,
                                        sendFailed: Bool,
                                        accepted: Bool,
                                        autoRetried: Bool) -> Bool {
        if accepted { return false }
        if heldOffline { return true }
        if sendFailed && !autoRetried { return true }
        return false
    }
}
