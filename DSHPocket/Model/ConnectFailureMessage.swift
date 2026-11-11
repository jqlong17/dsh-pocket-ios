// 连接失败分型：暂时性 / 认证失效 / 地址无效 / 未知

import Foundation
import DSHKit

/// 把连接失败归成四类，并给出下一步该做什么。
///
/// 为什么单独做这一层：
/// - 以前超时、断连、认证失效、地址错误最后都落到一句笼统的红字，用户不知道该「重试」还是「重新配对」。
///   同样是 20 秒没响应，网络抖一下要重试，二维码过期要重新扫码，这两件事必须长得不一样。
/// - 「是不是网络抖动」的判断在 DSHKit.DSHNetworkErrorPolicy 里已经有一份（自动重试就用它），
///   这里直接复用，不再写第二份瞬时错误表，避免两边慢慢走偏。
/// - 分类和文案放在同一个文件里：调用点只取结果，模型和视图不会各写一句、说法不一致。
///
/// 各类的边界：
/// - 暂时性：原地重试可能成功（超时、断连、无网络、DNS、限流）。提示「稍后重试」，`needsRescan` 为 false。
/// - 认证失效：凭据不对或过期（401/403、配对码失效、密码不对），重试没用，必须重新扫码或重新输密码。
/// - 地址无效：地址本身用不了（URL 解析失败、host 为空、证书对不上、公网隧道换了地址），要重新扫码取新地址。
/// - 未知：不猜原因，只给「先重试，还不行再重新配对」的兜底；原始错误类型留进诊断日志。
struct ConnectFailureMessage: Equatable {
    /// 失败类型。界面只需要知道「重试有没有用、要不要重新扫码」，所以类型只影响文案和 `needsRescan`。
    enum Kind: String, Equatable {
        /// 暂时性：超时、断连、无网络、DNS、限流。
        case transient
        /// 认证失效：401/403、配对码/登录 token/访问密码失效或不对。
        case auth
        /// 地址无效：URL 解析失败、host 为空、证书对不上、公网地址已变化。
        case invalidAddress
        /// 未知：其余情况。
        case unknown

        /// 写进诊断日志的中文标签，方便按类型捞记录。
        var label: String {
            switch self {
            case .transient: return "暂时性"
            case .auth: return "认证失效"
            case .invalidAddress: return "地址无效"
            case .unknown: return "未知"
            }
        }
    }

    /// 调用场景。同一个错误在不同流程里要指向不同的下一步动作：
    /// `invalidPin` 在一次性配对里是「二维码过期」，在密码登录里是「密码不对」。
    enum Context {
        /// 扫码后的一次性配对（POST /pair）。
        case pairing
        /// 带 ?token= 的登录链接。
        case loginToken
        /// 手动输入访问密码登录。
        case password
        /// 地址格式校验。
        case address
        /// 拉会话、切换地址、恢复连接等通用场景。
        case general
    }

    let kind: Kind
    /// 给用户看的一句话：短、具体、包含下一步动作。不写「操作失败」这类没有信息量的句子。
    let text: String
    /// 是否需要用户重新扫码/重新配对。true 时界面给「重新扫码」入口，而不是让用户原地重试。
    let needsRescan: Bool

    init(error: Error, context: Context = .general) {
        if let connectionError = error as? ConnectionError {
            self = Self.from(connectionError, context: context)
        } else if let urlError = error as? URLError {
            self = Self.from(urlError)
        } else if error is CancellationError {
            self = Self(.unknown, L10n.t("这次连接被取消了。等准备好了再点一次「连接」。"), needsRescan: false)
        } else {
            self = Self(.unknown, L10n.t("这次连接没有成功，原因没认出来。先点「连接」重试一次；反复这样的话，回电脑重新扫码配对。"), needsRescan: false)
        }
    }

    private init(_ kind: Kind, _ text: String, needsRescan: Bool) {
        self.kind = kind
        self.text = text
        self.needsRescan = needsRescan
    }
}

// MARK: - 输入校验（不是从 Error 来的，但同样属于「连接失败」文案，集中放这里）

extension ConnectFailureMessage {
    /// 手动输入/粘贴的地址格式不对（URL 解析失败、host 为空、协议不是 http/https）。
    static func addressFormatInvalid() -> ConnectFailureMessage {
        Self(.invalidAddress,
             L10n.t("地址格式不对：要 http:// 或 https:// 开头的电脑地址，例如 http://192.168.1.10:3081。也可以直接扫码。"),
             needsRescan: true)
    }

    /// 扫到的二维码里没有可用的 HTTP(S) 地址。
    static func scannedAddressInvalid() -> ConnectFailureMessage {
        Self(.invalidAddress,
             L10n.t("这个二维码里没有电脑地址（要 http:// 或 https:// 开头）。换成 DSH「手机访问」页面上的二维码再扫一次。"),
             needsRescan: true)
    }

    /// 访问密码格式不合法：只允许 8–64 位字母或数字，避免密码管理器填入的长密码被当成「密码错误」。
    static func pinFormatInvalid() -> ConnectFailureMessage {
        Self(.auth,
             L10n.t("访问密码要 8–64 位英文字母或数字。重新输入一次，别用密码管理器自动填入的长密码。"),
             needsRescan: false)
    }

    /// 还没输入访问密码就点了连接。
    static func pinMissing() -> ConnectFailureMessage {
        Self(.auth, L10n.t("先输入电脑上显示的访问密码，再点「连接」。"), needsRescan: false)
    }
}

// MARK: - 分类规则

private extension ConnectFailureMessage {
    /// DSH 自己抛的连接错误：认证、地址、限流、协议异常。
    static func from(_ error: ConnectionError, context: Context) -> ConnectFailureMessage {
        switch error {
        case .invalidPin:
            switch context {
            case .pairing:
                return Self(.auth,
                            L10n.t("配对二维码失效了（60 秒有效、只能用一次）。在电脑上重新生成二维码，再扫一次。"),
                            needsRescan: true)
            case .loginToken:
                return Self(.auth,
                            L10n.t("这个登录链接失效了（DSH 重启后 token 会变）。回电脑的「手机访问」重新复制地址，或改用访问密码登录。"),
                            needsRescan: true)
            case .password, .general, .address:
                return Self(.auth,
                            L10n.t("访问密码不对，或电脑那边改过密码。核对电脑上显示的密码再输一次；也可以回上一步重新扫码。"),
                            needsRescan: true)
            }
        case .invalidURL:
            return addressFormatInvalid()
        case .server(let code):
            return fromStatusCode(code)
        case .rateLimited(let seconds):
            return Self(.transient,
                        L10n.t("试得太频繁，电脑暂时挡住了。等 \(max(seconds, 1)) 秒再点「连接」就行，不用重新配对。"),
                        needsRescan: false)
        case .unexpectedResponse, .invalidPayload:
            return Self(.unknown,
                        L10n.t("电脑回的内容对不上，可能连到了别的服务，或 DSH 版本不一致。确认地址来自 DSH 的「手机访问」页，再试一次。"),
                        needsRescan: false)
        case .remote(let message):
            return Self(.unknown,
                        L10n.t("电脑那边回了错误：\(message)。先点「连接」重试一次；反复出现就回电脑重新扫码配对。"),
                        needsRescan: false)
        }
    }

    /// HTTP 状态码：401/403 是认证，隧道 5xx 是地址换了，其余 5xx 先当暂时性（重试比重新配对更可能有效）。
    static func fromStatusCode(_ code: Int) -> ConnectFailureMessage {
        if code == 401 || code == 403 {
            return Self(.auth,
                        L10n.t("登录失效了（电脑可能重启过 DSH，或改过密码）。重新扫一次码，或重新输入访问密码。"),
                        needsRescan: true)
        }
        if tunnelDownStatusCodes.contains(code) {
            return Self(.invalidAddress,
                        L10n.t("电脑的公网隧道连不上（HTTP \(code)），公网地址多半已经换了。在电脑上重新打开「手机访问」再扫一次码；同一 Wi-Fi 也可以改用局域网地址。"),
                        needsRescan: true)
        }
        if (500..<600).contains(code) {
            return Self(.transient,
                        L10n.t("电脑那边出错了（HTTP \(code)），像是暂时的。等一会儿再点「连接」就行，不用重新配对。"),
                        needsRescan: false)
        }
        return Self(.unknown,
                    L10n.t("电脑回了 HTTP \(code)，不像是网络断了。先点「连接」重试一次；还是这样就回电脑重新扫码配对。"),
                    needsRescan: false)
    }

    /// URLSession 的网络错误。先处理证书/地址，再复用 DSHNetworkErrorPolicy 判断瞬时故障。
    static func from(_ error: URLError) -> ConnectFailureMessage {
        switch error.code {
        case .timedOut:
            return Self(.transient,
                        L10n.t("电脑没有响应（连接超时）。多半是电脑正忙或路上网络不稳，等几秒再点「连接」就行，不用重新配对。"),
                        needsRescan: false)
        case .notConnectedToInternet:
            return Self(.transient,
                        L10n.t("手机现在没有网络。先连上 Wi-Fi 或蜂窝，再点「连接」就行，不用重新配对。"),
                        needsRescan: false)
        case .networkConnectionLost:
            return Self(.transient,
                        L10n.t("连接中途断了（Wi-Fi 切换或信号抖动）。等网络稳定后点「连接」就行，不用重新配对。"),
                        needsRescan: false)
        case .cannotConnectToHost:
            return Self(.transient,
                        L10n.t("连不上这台电脑。确认电脑还开着 DSH、手机和电脑在同一个网络，再点「连接」；不用重新配对。"),
                        needsRescan: false)
        case .cannotFindHost, .dnsLookupFailed:
            return Self(.transient,
                        L10n.t("找不到这台电脑（地址解析失败）。检查地址有没有写错、电脑是否在线，再点「连接」；不用重新配对。"),
                        needsRescan: false)
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            return Self(.invalidAddress,
                        L10n.t("这个地址的 HTTPS 证书对不上（公网地址可能已经变了）。在电脑上重新打开「手机访问」再扫一次码；同一 Wi-Fi 也可以改用局域网地址。"),
                        needsRescan: true)
        case .userAuthenticationRequired:
            return Self(.auth,
                        L10n.t("电脑要求先登录，这一步没通过。重新扫一次码，或重新输入访问密码。"),
                        needsRescan: true)
        case .badURL, .unsupportedURL, .appTransportSecurityRequiresSecureConnection:
            return addressFormatInvalid()
        default:
            // 剩余情况交给 DSHKit 那一份瞬时判断，保持和自动重试的边界一致。
            if DSHNetworkErrorPolicy.isTransient(error) {
                return Self(.transient,
                            L10n.t("网络暂时不通。等几秒再点「连接」就行，不用重新配对。"),
                            needsRescan: false)
            }
            return Self(.unknown,
                        L10n.t("这次连接没有成功，原因没认出来。先点「连接」重试一次；反复这样的话，回电脑重新扫码配对。"),
                        needsRescan: false)
        }
    }
}

// MARK: - 诊断与「地址是否已失效」

extension ConnectFailureMessage {
    /// 公网隧道下线的状态码（Cloudflare quick tunnel 重启后常见）。这些不是网络抖动，是地址已经不能用了。
    static let tunnelDownStatusCodes: Set<Int> = [502, 503, 504, 520, 521, 522, 523, 524, 530]

    /// 证书类错误：地址对得上的 HTTPS 不该失败，失败基本意味着公网地址换了。
    static let certificateErrorCodes: Set<URLError.Code> = [
        .secureConnectionFailed,
        .serverCertificateUntrusted,
        .serverCertificateHasBadDate,
        .serverCertificateNotYetValid,
        .serverCertificateHasUnknownRoot,
        .clientCertificateRejected
    ]

    /// 是否是「公网隧道地址已失效 / 证书对不上」这类错误。
    /// 自动重试（Live、会话列表）用它把「该重新扫码」和「该退避重试」区分开。
    static func isStaleTunnel(_ error: Error) -> Bool {
        if let connectionError = error as? ConnectionError,
           case .server(let code) = connectionError {
            return tunnelDownStatusCodes.contains(code)
        }
        if let urlError = error as? URLError {
            return certificateErrorCodes.contains(urlError.code)
        }
        return false
    }

    /// 诊断日志里的原始错误，保留类型和 code，不把地址里可能存在的 token 写出去。
    /// 用户看到的红字是分型文案，排查时需要的是这一行，所以两者都要留。
    static func diagnosticText(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return "URLError(\(urlError.code.rawValue))：\(urlError.localizedDescription)"
        }
        if let connectionError = error as? ConnectionError {
            if case .invalidURL = connectionError {
                return "ConnectionError(invalidURL)：地址已省略"
            }
            return "ConnectionError(\(String(describing: connectionError)))：\(connectionError.localizedDescription)"
        }
        return "\(type(of: error))：\(error.localizedDescription)"
    }
}
