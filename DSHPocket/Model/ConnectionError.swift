// ConnectionError

import SwiftUI
import Security
import Textual
import DSHKit
import VisionKit
import AVFoundation
import Observation
import PhotosUI
import UIKit
import Photos
import os
import AudioToolbox
import ImageIO
import UserNotifications


enum ConnectionError: LocalizedError {
    case invalidPin, unexpectedResponse, invalidPayload, invalidURL(String), server(Int), rateLimited(Int), remote(String)
    var errorDescription: String? {
        switch self {
        case .invalidPin: L10n.t("密码不正确或已变更，请重新输入访问密码。")
        case .unexpectedResponse: "服务器返回了无法识别的响应。"
        case .invalidPayload: "服务器响应格式无效。"
        case .invalidURL(let raw): "地址格式无效：\(raw.debugDescription)。请输入 http://192.0.2.10:3081 这样的地址。"
        case .server(let code): "服务器暂时无法连接（HTTP \(code)）。"
        case .rateLimited(let seconds): "尝试次数过多，请 \(max(seconds, 1)) 秒后再试。"
        case .remote(let message): message
        }
    }
}

extension ConnectionError {
    /// 把 DSHKit 的协议错误适配成 App 的展示错误。
    ///
    /// 为什么需要这层：`DSHErrorKind` 负责「怎么处理」（可单测，在 DSHKit），
    /// `ConnectionError` 负责「怎么显示」（文案/dialect），两者职责不同。
    /// 传输层错误（URLError）不走这里——它原样向上抛，供 `isTransientNetworkError` 判断。
    static func from(_ error: DSHError, address: String) -> ConnectionError {
        switch error {
        case .invalidAddress:
            return .invalidURL(address)
        case .unauthorized:
            // 401/403 在 App 语义里就是「访问密码不对/已变更」。
            return .invalidPin
        case .rateLimited:
            return .rateLimited(1)
        case .invalidPayload, .decoding:
            return .invalidPayload
        case let .server(status, message):
            if let message, !message.isEmpty { return .remote(message) }
            return .server(status)
        case .transport:
            return .unexpectedResponse
        }
    }
}

extension ConnectionError {
    /// 是不是「登录失效」。
    ///
    /// 为什么要这个判断而不是直接 `case .server(401)`：
    /// RPC 收口后 401 会被 `from(_:address:)` 适配成 `.invalidPin`（给用户看「密码不正确」更准），
    /// 于是原先所有 `case .server(401)` 的判断全部失效——连不上时既不提示重新配对、
    /// 也不触发设备凭证换票，表现成每两秒重试一次「密码不正确」。
    /// 这里把两种形态统一起来，判断点只认这一个属性。
    var isUnauthorized: Bool {
        switch self {
        case .invalidPin: return true
        case .server(let status): return status == 401 || status == 403
        case .rateLimited: return false
        case .invalidURL, .unexpectedResponse, .invalidPayload, .remote: return false
        }
    }
}
