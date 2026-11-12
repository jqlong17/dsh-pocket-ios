import Foundation

/// 错误的处理类别：决定「要不要重试」和「怎么提示」，与文案无关。
///
/// 为什么独立于 `ConnectionError`：分类是纯判断，必须可测；
/// 文案属于 UI（App 层）。以前两者混在一起，20 处调用点各自判断，收口后统一到这里。
public enum DSHErrorKind: Equatable, Sendable {
    /// 网络抖动、超时、5xx、429：值得重试。
    case transient
    /// 401/403：重新登录，重试无意义。
    case auth
    /// 地址不可用（格式错、解析不到）。
    case invalidAddress
    /// 业务失败（4xx、解析失败、服务端明确拒绝）。
    case business
}

/// DSH 协议/传输层错误（模块 01）。UI 层再映射为可读文案。
public enum DSHError: Error, Equatable, Sendable {
    case invalidAddress
    case invalidPayload
    case unauthorized
    case rateLimited
    case server(status: Int, message: String?)
    case transport(String)
    case decoding(String)

    /// 处理类别。
    public var kind: DSHErrorKind {
        switch self {
        case .transport:
            return .transient
        case .rateLimited:
            return .transient
        case .unauthorized:
            return .auth
        case .invalidAddress:
            return .invalidAddress
        case let .server(status, _):
            // 5xx 是服务端暂时不可用，可重试；4xx 是请求本身有问题，重试只会重复失败。
            return (500..<600).contains(status) ? .transient : .business
        case .invalidPayload, .decoding:
            return .business
        }
    }

    /// 是否值得重试（等价于 `kind == .transient`，单独暴露是为了调用点语义清晰）。
    public var isRetryable: Bool { kind == .transient }

    /// 按 HTTP 状态码映射错误；用于 RPC 响应统一处理。
    public static func from(status: Int, message: String? = nil) -> DSHError? {
        switch status {
        case 200..<300: return nil
        case 401, 403: return .unauthorized
        case 429: return .rateLimited
        default: return .server(status: status, message: message)
        }
    }
}
