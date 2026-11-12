import Foundation

/// RPC 重试策略：什么错误值得重试、退避多久。
///
/// 为什么抽成纯类型而不是写在网络调用里：
/// - 「401 被重试 3 次」这种 bug 在生产里表现为「密码错了却一直转圈」，只有穷举测试才拦得住；
/// - 退避节奏是产品行为（用户能感知等待），调它不该动网络代码。
///
/// 铁律：**只有瞬时错误才重试**。业务错误（401/403/400）重试无意义，只会放大等待。
public enum RPCRetryPolicy {
    /// 退避节奏（毫秒）：首次 800，之后 2000，上限 3000。
    /// 沿用 App 层旧实现的 800/2000，避免改变用户可感知的发送体验。
    private static let backoffMilliseconds: [Int] = [800, 2000, 3000]

    public static func shouldRetry(_ error: Error, attempt: Int, maxAttempts: Int) -> Bool {
        guard attempt < maxAttempts - 1 else { return false }
        return DSHNetworkErrorPolicy.isTransient(error)
    }

    public static func backoff(attempt: Int) -> Duration {
        let index = min(max(attempt, 0), backoffMilliseconds.count - 1)
        return .milliseconds(backoffMilliseconds[index])
    }
}
