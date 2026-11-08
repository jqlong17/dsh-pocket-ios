import Foundation

/// DSH 协议/传输层错误（模块 01）。UI 层再映射为可读文案。
public enum DSHError: Error, Equatable, Sendable {
    case invalidAddress
    case invalidPayload
    case unauthorized
    case rateLimited
    case server(status: Int, message: String?)
    case transport(String)
    case decoding(String)

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
