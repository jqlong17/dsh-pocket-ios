// NotificationBridge

import Foundation
import UIKit
import DSHKit

/// 通知 / Apple Watch 相关的三件事：注册推送、直接回复、从通知打开会话。
///
/// 边界（spec/12）：只做「通知域」的编排，不碰消息内容与实时流。
/// 依赖全部通过闭包注入——这些能力要读模型状态（连接、会话列表、发件箱），
/// 但模型不该反过来知道通知细节。
final class NotificationBridge {
    struct Providers {
        var client: () throws -> DSHClient
        var isConnected: () -> Bool
        var pin: () -> String
        var setPin: (String) -> Void
        var savedPin: () -> String?
        var savedAddress: () -> String?
        var serverAddress: () -> String
        var setServerAddress: (String) -> Void
        /// 未连接时自动重连（内部会补地址与密码）。
        var connect: @MainActor () async -> Void
        var sessions: () -> [PocketSession]
        /// 打开会话（设置导航路径）。
        var openSession: @MainActor (String) -> Void
        var insertAckedRpcId: (String) -> Void
        var addOutbox: (String, String, String) -> Void
        var clearFinishedAwaiting: (String) -> Void
        var completionAlertsEnabled: () -> Bool
        var pushToken: () -> String?
        var record: (String) -> Void
    }

    var providers: Providers?

    /// 登录成功后把 APNs token 注册到插件；通知权限未开启时先申请。
    @MainActor
    func syncPushRegistration() async {
        guard let providers else { return }
        guard providers.completionAlertsEnabled() else {
            if let token = providers.pushToken() {
                _ = try? await providers.client().rpcAdapted("push.unregister", args: ["token": token])
            }
            return
        }
        UIApplication.shared.registerForRemoteNotifications()
        guard let token = providers.pushToken(), providers.isConnected() else { return }
        do {
            _ = try await providers.client().rpcAdapted("push.register", args: [
                "token": token,
                "environment": "sandbox",
                "bundleId": Bundle.main.bundleIdentifier ?? "",
                "deviceName": UIDevice.current.name
            ])
            providers.record("APNs token 已注册（\(token.suffix(6))）")
        } catch {
            providers.record("APNs token 注册失败：\(error.localizedDescription)")
        }
    }

    /// 通知 / Apple Watch 直接回复：把文本作为 prompt 发回指定会话。
    /// 冷启动时用 Keychain 里的密码自动重连；失败只记录诊断，不打断前台。
    @MainActor
    func sendReply(sessionId: String, text: String) async {
        guard !text.isEmpty, let providers else { return }
        providers.record("通知回复：会话 \(sessionId)，\(text.count) 字")
        let background = UIApplication.shared.beginBackgroundTask(withName: "dsh-notification-reply")
        defer {
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
        }

        if !providers.isConnected() {
            if let saved = providers.savedAddress(), !saved.isEmpty {
                providers.setServerAddress(saved)
            }
            if providers.pin().isEmpty, let savedPin = providers.savedPin() {
                providers.setPin(savedPin)
            }
            if providers.pin().isEmpty {
                providers.record("通知回复失败：未连接且没有可用密码")
                return
            }
            await providers.connect()
            guard providers.isConnected() else {
                providers.record("通知回复失败：自动重连未成功")
                return
            }
        }

        // 通知回复一律排队：列表里的 running 可能滞后，误打断比晚一轮更糟。
        let mode = PromptPolicy.replyMode(
            isRunning: providers.sessions().first { $0.sessionId == sessionId }?.running ?? false
        ).rawValue
        let requestId = UUID().uuidString.lowercased()
        do {
            _ = try await providers.client().rpcWithRetryAdapted("session/prompt", args: ["request": [
                "requestId": requestId,
                "sessionId": sessionId,
                "mode": mode,
                "content": [["type": "text", "text": text]],
                "clientTimeZone": TimeZone.current.identifier
            ]])
            providers.insertAckedRpcId(requestId)
            providers.addOutbox(sessionId, requestId, text)
            providers.clearFinishedAwaiting(sessionId)
            providers.record("通知回复已发送（模式 \(mode)）")
        } catch {
            providers.record("通知回复发送失败：\(error.localizedDescription)")
        }
    }

    /// 从通知点进来：确保已连接，然后打开对应会话。
    @MainActor
    func openSessionFromNotification(sessionId: String) async {
        guard let providers else { return }
        if !providers.isConnected() {
            if providers.pin().isEmpty, let savedPin = providers.savedPin() {
                providers.setPin(savedPin)
            }
            if providers.pin().isEmpty, let saved = providers.savedAddress(), !saved.isEmpty {
                providers.setServerAddress(saved)
            }
            await providers.connect()
        }
        guard providers.sessions().contains(where: { $0.sessionId == sessionId }) else {
            providers.record("通知打开会话失败：找不到 \(sessionId)")
            return
        }
        providers.clearFinishedAwaiting(sessionId)
        providers.openSession(sessionId)
    }
}
