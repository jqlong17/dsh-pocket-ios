import Foundation

/// 发送失败后该怎么处置这条消息。
///
/// 这是数据安全语义：处置错了要么丢正文（11-12 事故），要么把「其实已发出」判成失败让用户重发。
/// 原先这几个分支内联在 performSend 的 catch 里（约 60 行），顺序还不能乱：
/// 先判取消（用户意图最高）、再判登录失效、再判网络、最后才判失败。
public enum SendFailureAction: Equatable, Sendable {
    /// 用户取消：正文退回输入框，然后才可以删本机副本。
    case returnToComposer
    /// 登录失效：正文保留在发件箱，重新登录后可重发；同时要提示重新登录。
    case reauthenticate
    /// 网络不通：写断网标记，联网后按顺序补发。**不判失败**。
    case holdOffline
    /// 其它失败：标记失败，用户可点重发。正文仍保留。
    case markFailed
}

public enum SendFailurePolicy {
    /// - Parameters:
    ///   - isCancelled: 任务是否被取消（Task.isCancelled 或 URLError.cancelled）。
    ///   - isUnauthorized: 是否 401/403。
    ///   - isTransient: 是否瞬时网络故障（URLError 白名单）。
    ///   - isStaleTunnel: 是否隧道地址过期（这类错误重试无意义）。
    public static func action(isCancelled: Bool,
                              isUnauthorized: Bool,
                              isTransient: Bool,
                              isStaleTunnel: Bool) -> SendFailureAction {
        if isCancelled { return .returnToComposer }
        if isUnauthorized { return .reauthenticate }
        if isTransient && !isStaleTunnel { return .holdOffline }
        return .markFailed
    }
}
