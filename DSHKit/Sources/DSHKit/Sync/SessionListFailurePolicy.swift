import Foundation

/// 会话列表刷新失败后的处置。
///
/// 这段判定原先内联在 loadSessions 的 catch 里，四条规则都是踩过坑才有的：
/// 1. 取消不算失败（页面已切走）；
/// 2. 401 要回连接页，重试没有意义；
/// 3. 隧道地址过期要直接报错，不能一直"正在重试"；
/// 4. 后台静默刷新遇到抖动**不要**顶红字——用户没做任何操作却被吓一跳。
public enum SessionListFailureAction: Equatable, Sendable {
    /// 不处理（任务取消）。
    case ignore
    /// 登录失效：回连接页。
    case reauthenticate
    /// 地址失效（隧道重建）：直接报错并引导重新扫码。
    case showAddressError
    /// 网络抖动且已有列表：保留现状，后台退避重试。
    case retryQuietly
    /// 真要告诉用户。
    case showMessage(String)
}

public enum SessionListFailurePolicy {
    public static func action(isCancelled: Bool,
                              isUnauthorized: Bool,
                              isStaleTunnel: Bool,
                              isTransient: Bool,
                              isSilent: Bool,
                              hasExistingSessions: Bool,
                              message: String) -> SessionListFailureAction {
        if isCancelled { return .ignore }
        if isUnauthorized { return .reauthenticate }
        if isStaleTunnel { return .showAddressError }
        if isTransient && (isSilent || hasExistingSessions) { return .retryQuietly }
        return .showMessage(message)
    }
}
