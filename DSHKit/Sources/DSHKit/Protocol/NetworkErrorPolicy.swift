import Foundation

/// 瞬时网络错误判断。原先 App 里有两份几乎相同但不完全一致的实现，这里收口为并集。
public enum DSHNetworkErrorPolicy {
    /// 可重试的瞬时网络故障。不含业务错误，也不把过期隧道等语义错误算进来。
    public static func isTransient(_ error: Error) -> Bool {
        // 兜底：其它传输实现若仍把网络错误包成 DSHError.transport，
        // 语义上依然是「没连上/连接断了」，属于可重试的瞬时故障。
        if case .transport = error as? DSHError { return true }
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut,
             .networkConnectionLost,
             .notConnectedToInternet,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }
}
