// 生命周期、选区、推送、钥匙串和调试日志

let pocketLogger = Logger(subsystem: "com.ruska.dsh-pocket-ios", category: "conversation")

func timingLog(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) DSH_TIMING \(message)"
    NSLog("%@", line)
}

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


extension Notification.Name { static let appLanguageChanged = Notification.Name("dsh-pocket.language-changed") }


/// 读屏播报。VoiceOver 关着时不发，避免干扰。
enum AccessibilityAnnouncer {
    static func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}


/// 还活着的会话页数量。退出后应该回到 0；如果一直涨，就是页面没释放。
enum ConversationViewLifetime {
    static var liveCount = 0
}


/// Textual 没有公开清除选区的 API：直接定位当前第一响应者的文本输入视图，
/// 把它选中的范围置空（不重建视图，避免列表闪动/跳到底部）。
enum TextSelectionDismisser {
    static func clear() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if let responder = findFirstResponder(in: window), let input = responder as? UITextInput {
                    input.selectedTextRange = nil
                    responder.resignFirstResponder()
                    return
                }
            }
        }
    }

    private static func findFirstResponder(in view: UIView) -> UIResponder? {
        if view.isFirstResponder { return view }
        for subview in view.subviews {
            if let responder = findFirstResponder(in: subview) { return responder }
        }
        return nil
    }
}


extension Notification.Name {
    static let dshPushTokenUpdated = Notification.Name("dsh-pocket.push-token-updated")
}


/// APNs device token 回调（SwiftUI 生命周期下用 delegate adaptor 接收）。
final class PushDelegate: NSObject, UIApplicationDelegate {
    static let tokenDefaultsKey = "dsh-pocket.apns-token"

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: Self.tokenDefaultsKey)
        NotificationCenter.default.post(name: .dshPushTokenUpdated, object: token)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("DSH_PUSH register failed: %@", error.localizedDescription)
    }
}


/// 访问密码存 Keychain：通知回复在后台/冷启动时需要自动重连。
enum PinKeychain {
    private static let service = "com.ruska.dsh-pocket-ios.pin"
    private static let account = "access-pin"

    static func save(_ pin: String) {
        guard !pin.isEmpty else { clear(); return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(pin.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let pin = String(data: data, encoding: .utf8) else { return nil }
        return pin
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// 服务器地址与登录 cookie 的 Keychain 存储。
///
/// 为什么要用 Keychain 而不是 UserDefaults：
/// 调试时反复 `devicectl install` 覆盖安装会清掉沙盒（UserDefaults 和 HTTPCookieStorage 都在里面），
/// 每次都要重新扫码配对。Keychain 数据在 App 被替换后仍然保留，
/// 所以把「地址 + dsh-auth cookie」放这里，重装后能自动恢复连接。
enum ConnectionVault {
    private static let addressService = "com.ruska.dsh-pocket-ios.address"
    private static let cookieService = "com.ruska.dsh-pocket-ios.auth-cookie"
    private static let account = "default"

    // MARK: 地址

    static func saveAddress(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "http://" else { return }
        write(trimmed, service: addressService)
    }

    static func loadAddress() -> String? {
        read(service: addressService)
    }

    // MARK: 长期设备凭证

    private static let deviceService = "com.ruska.dsh-pocket-ios.device"

    /// 配对后插件会种一个 `dsh-pocket-device` cookie；把它单独存进 Keychain，
    /// 用来在 DSH 重启、session cookie 失效时静默换新票，不必重新扫码。
    static func saveDeviceToken(from url: URL) {
        let token = HTTPCookieStorage.shared.cookies(for: url)?
            .first { $0.name == "dsh-pocket-device" }?.value
        guard let token, !token.isEmpty else { return }
        write(token, service: deviceService)
    }

    static func loadDeviceToken() -> String? {
        read(service: deviceService)
    }

    static func clearDeviceToken() {
        delete(service: deviceService)
    }

    // MARK: 登录 cookie

    /// 只保存 dsh-auth 开头的 cookie（其余是无关的会话 cookie）。
    static func saveAuthCookies(from url: URL) {
        let cookies = HTTPCookieStorage.shared.cookies(for: url)?
            .filter { $0.name.hasPrefix("dsh-auth") } ?? []
        guard !cookies.isEmpty else { return }
        let payload = cookies.map { cookie -> [String: Any] in
            var dict: [String: Any] = [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path
            ]
            if let expires = cookie.expiresDate {
                dict["expires"] = expires.timeIntervalSince1970
            }
            return dict
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        write(String(decoding: data, as: UTF8.self), service: cookieService)
    }

    /// 把保存过的 cookie 放回 HTTPCookieStorage；过期的直接丢弃。
    static func restoreAuthCookies(to url: URL) {
        guard let raw = read(service: cookieService),
              let data = raw.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        var restored: [HTTPCookie] = []
        for item in list {
            guard let name = item["name"] as? String,
                  let value = item["value"] as? String,
                  let domain = item["domain"] as? String,
                  let path = item["path"] as? String else { continue }
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: name, .value: value, .domain: domain, .path: path
            ]
            if let expires = item["expires"] as? TimeInterval {
                let date = Date(timeIntervalSince1970: expires)
                guard date > Date() else { continue }
                props[.expires] = date
            }
            if let cookie = HTTPCookie(properties: props) {
                restored.append(cookie)
            }
        }
        guard !restored.isEmpty else { return }
        HTTPCookieStorage.shared.setCookies(restored, for: url, mainDocumentURL: nil)
    }

    /// 彻底忘记这台电脑：地址与登录 cookie 一并清除。
    /// 「断开连接」不调用它（用户只是暂时不连）；只有「删除这台电脑」才清。
    static func clear() {
        delete(service: addressService)
        delete(service: cookieService)
        delete(service: deviceService)
    }

    /// 只清登录 cookie（认证失效时用，避免拿废凭证反复失败）。
    static func clearAuthCookies() {
        delete(service: cookieService)
    }

    // MARK: 底层读写

    private static func write(_ value: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func delete(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func read(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
