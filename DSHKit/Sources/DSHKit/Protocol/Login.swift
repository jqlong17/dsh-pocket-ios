import Foundation

/// 登录结果分类（用例 P10–P12）。
public enum LoginOutcome: Equatable, Sendable {
    case success
    case invalidPIN
    case rateLimited
    case serverError(status: Int)
}

public enum LoginClassifier {
    /// DSH 协议：正确 PIN → 302 + pocket cookie；错误 PIN → 200 登录页；频繁尝试 → 429。
    public static func outcome(statusCode: Int, redirected: Bool, hasPocketCookie: Bool) -> LoginOutcome {
        switch statusCode {
        case 200..<300:
            return redirected && hasPocketCookie ? .success : .invalidPIN
        case 300..<400:
            return redirected && hasPocketCookie ? .success : .serverError(status: statusCode)
        case 401, 403:
            return .invalidPIN
        case 429:
            return .rateLimited
        default:
            return .serverError(status: statusCode)
        }
    }
}
