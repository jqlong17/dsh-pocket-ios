import Foundation

/// 发件箱里的正文什么时候可以从本机删掉。
///
/// 铁律：只有「服务端已确认」或「用户明确取消（正文已回到输入框）」才允许删。
/// 网络失败、发送失败、登录失效都必须留着——2026-11-12 就是因为先删后发，
/// 断网期间排队的 6 条消息从本机和服务器同时消失。
public enum OutboxRetentionPolicy {
    public enum RemovalCause: Equatable {
        /// 服务端历史里确认到了这条消息。
        case serverConfirmed
        /// 用户点了取消，正文已退回输入框。
        case userCancelled
        /// 网络不通或超时。
        case networkFailure
        /// 服务端明确说没收到。
        case sendFailed
        /// 登录失效（401/403）。
        case authExpired
    }

    public static func canRemove(cause: RemovalCause) -> Bool {
        switch cause {
        case .serverConfirmed, .userCancelled: return true
        case .networkFailure, .sendFailed, .authExpired: return false
        }
    }
}
