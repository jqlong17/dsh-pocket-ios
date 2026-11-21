// 生命周期、选区、推送、钥匙串和调试日志

let pocketLogger = Logger(subsystem: "com.ruska.dsh-pocket-ios", category: "conversation")

/// 会话 id 的短形式：`session-76527050-...` → `76527050`。
///
/// 直接 `suffix(8)` 会拿到 `session-`（前 8 位是固定前缀），日志里等于没记。
func shortSessionId(_ id: String) -> String {
    let stripped = id.hasPrefix("session-") ? String(id.dropFirst("session-".count)) : id
    return String(stripped.prefix(8))
}

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
    /// 注册失败原因。`didFail` 只在这里能拿到，必须落盘让遥测带出去——
    /// NSLog 走 os_log，`devicectl --console` 抓不到，只能靠 App 自己上报。
    static let errorDefaultsKey = "dsh-pocket.apns-error"
    /// 最近一次「发起注册」的时刻。用来判断「函数根本没被调用」还是「被系统拒绝」。
    static let attemptDefaultsKey = "dsh-pocket.apns-attempt-at"

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: Self.tokenDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.errorDefaultsKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.attemptDefaultsKey)
        NotificationCenter.default.post(name: .dshPushTokenUpdated, object: token)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        let ns = error as NSError
        UserDefaults.standard.set(
            "\(ns.domain) \(ns.code): \(ns.localizedDescription)",
            forKey: Self.errorDefaultsKey
        )
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.attemptDefaultsKey)
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
    private static let cookieServiceBase = "com.ruska.dsh-pocket-ios.auth-cookie"
    private static let account = "default"

    /// 把地址归一化成 Keychain key 的一部分。
    ///
    /// 为什么要按地址隔离：之前设备凭证和 cookie 只有**一份**全局的。
    /// 用户保存了多台电脑/多种连接方式（家里局域网、公司、云服务器隧道），
    /// 切到另一个地址时那份凭证对不上，只能重新输密码——
    /// 而历史连接的意义就是「点一下就回去」（2026-11-15 用户反馈）。
    /// 现在每个 host:port 各存一份，互不覆盖。
    private static func vaultKey(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host else {
            // 解析不出来就退化成原文（去掉会破坏 Keychain 的字符）
            return trimmed.replacingOccurrences(of: "/", with: "_")
        }
        let port = url.port.map { "-\($0)" } ?? ""
        return "\(host)\(port)"
    }

    private static func cookieService(_ address: String) -> String {
        "\(cookieServiceBase).\(vaultKey(address))"
    }

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

    private static let deviceServiceBase = "com.ruska.dsh-pocket-ios.device"

    private static func deviceService(_ address: String) -> String {
        "\(deviceServiceBase).\(vaultKey(address))"
    }

    /// 配对后插件会种一个 `dsh-pocket-device` cookie；把它单独存进 Keychain，
    /// 用来在 DSH 重启、session cookie 失效时静默换新票，不必重新扫码。
    static func saveDeviceToken(from url: URL, address: String) {
        let token = HTTPCookieStorage.shared.cookies(for: url)?
            .first { $0.name == "dsh-pocket-device" }?.value
        guard let token, !token.isEmpty else { return }
        write(token, service: deviceService(address))
    }

    /// 取某个地址的设备凭证。地址为 nil 时返回 nil（没有地址就无从查起）。
    static func loadDeviceToken(for address: String?) -> String? {
        guard let address, !address.isEmpty else { return nil }
        return read(service: deviceService(address))
    }

    static func clearDeviceToken(for address: String) {
        delete(service: deviceService(address))
    }

    // MARK: 登录 cookie

    /// 只保存 dsh-auth 开头的 cookie（其余是无关的会话 cookie）。
    static func saveAuthCookies(from url: URL, address: String) {
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
        write(String(decoding: data, as: UTF8.self), service: cookieService(address))
    }

    /// 把保存过的 cookie 放回 HTTPCookieStorage；过期的直接丢弃。
    static func restoreAuthCookies(to url: URL, address: String) {
        guard let raw = read(service: cookieService(address)),
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
    static func clear(address: String) {
        delete(service: addressService)
        delete(service: cookieService(address))
        delete(service: deviceService(address))
    }

    /// 只清登录 cookie（认证失效时用，避免拿废凭证反复失败）。
    static func clearAuthCookies(for address: String) {
        delete(service: cookieService(address))
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
