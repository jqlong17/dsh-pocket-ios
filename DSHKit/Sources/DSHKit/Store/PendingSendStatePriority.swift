import Foundation

/// 待确认消息该显示哪种状态。
///
/// 为什么单独定优先级：三种标记可能同时残留（例如断网时标了 queued，联网后补发成功
/// 只清了一部分）。此时显示哪个直接决定用户是否被误导：
/// - `failed` 最高：失败必须让用户看见并能点重发；
/// - `acked` 次之：**服务端已经受理**的消息，绝不能因为一个残留的断网标记就显示「现在断网」；
/// - `queued` 再次；
/// - 都没有才是「发送中」。
public enum PendingSendStatePriority: Equatable, Sendable {
    case failed
    case acked
    case queued
    case sending

    public static func resolve(failed: Bool, acked: Bool, queued: Bool) -> PendingSendStatePriority {
        if failed { return .failed }
        if acked { return .acked }
        if queued { return .queued }
        return .sending
    }
}
