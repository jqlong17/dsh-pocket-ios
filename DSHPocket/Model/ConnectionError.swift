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
