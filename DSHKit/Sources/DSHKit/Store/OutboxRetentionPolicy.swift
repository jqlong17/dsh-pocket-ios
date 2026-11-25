import Foundation

/// 发件箱里的正文什么时候可以从本机删掉。
///
/// 铁律：只有「服务端已确认」或「用户明确丢弃（取消 / 删除）」才允许删。
/// 网络失败、发送失败、登录失效都必须留着——2026-11-12 就是因为先删后发，
/// 断网期间排队的 6 条消息从本机和服务器同时消失。
/// 注意 `.userDiscarded` 是 2026-11-25 新增的显式出口：失败消息默认仍保留，
/// 只有用户在气泡下方点了「删除」并确认才走这里。
public enum OutboxRetentionPolicy {
    public enum RemovalCause: Equatable {
        /// 服务端历史里确认到了这条消息。
        case serverConfirmed
        /// 用户点了取消，正文已退回输入框。
        case userCancelled
        /// 用户点了失败消息下方的「删除」，明确丢弃正文（不回填输入框）。
        /// 只由 UI 的删除动作触发；自动路径一律不得使用。
        case userDiscarded
        /// 网络不通或超时。
        case networkFailure
        /// 服务端明确说没收到。
        case sendFailed
        /// 登录失效（401/403）。
        case authExpired
    }

    public static func canRemove(cause: RemovalCause) -> Bool {
        switch cause {
        case .serverConfirmed, .userCancelled, .userDiscarded: return true
        case .networkFailure, .sendFailed, .authExpired: return false
        }
    }
}
