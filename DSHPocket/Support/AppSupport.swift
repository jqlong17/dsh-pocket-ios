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
