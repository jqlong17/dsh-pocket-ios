// 通知域

import Foundation
import UIKit
import DSHKit

/// 通知 / Apple Watch 相关的三件事：注册推送、直接回复、从通知打开会话。
///
/// 边界：只做「通知域」的编排，不碰消息内容与实时流。
/// 用 extension 而非独立类型：自有状态为 0，原 17 个闭包注入只是用 DI 模拟「我是模型的一部分」。
/// 依赖全部通过闭包注入——这些能力要读模型状态（连接、会话列表、发件箱），
/// 但模型不该反过来知道通知细节。
extension ConnectionModel {
    /// 按 sessionId 打开会话（设置导航路径）。
    @MainActor
    func openSession(_ sessionId: String) {
        guard let session = sessionStore.sessions.first(where: { $0.sessionId == sessionId }) else { return }
        sessionStore.navigationPath = [session]
    }

    /// 打开/回复后清掉「已完成待回复」红点（与原 providers.clearFinishedAwaiting 行为一致）。
    @MainActor
    func clearFinishedAwaiting(_ sessionId: String) {
        if finishedAwaitingSessionIds.remove(sessionId) != nil { persistFinishedAwaiting() }
    }

    /// 登录成功后把 APNs token 注册到插件；通知权限未开启时先申请。
    @MainActor
    func syncPushRegistration() async {
        // 无前置条件
        guard completionAlertsEnabled else {
            if let token = pushToken {
                _ = try? await rpcClient.rpcAdapted("push.unregister", args: ["token": token])
            }
            return
        }
        UIApplication.shared.registerForRemoteNotifications()
        guard let token = pushToken, connection.isConnected else { return }
        do {
            _ = try await rpcClient.rpcAdapted("push.register", args: [
                "token": token,
                "environment": "sandbox",
                "bundleId": Bundle.main.bundleIdentifier ?? "",
                "deviceName": UIDevice.current.name
            ])
            recordDiagnostic("APNs token 已注册（\(token.suffix(6))）")
        } catch {
            recordDiagnostic("APNs token 注册失败：\(error.localizedDescription)")
        }
    }

    /// 通知 / Apple Watch 直接回复：把文本作为 prompt 发回指定会话。
    /// 冷启动时用 Keychain 里的密码自动重连；失败只记录诊断，不打断前台。
    @MainActor
    func sendNotificationReply(sessionId: String, text: String) async {
        guard !text.isEmpty else { return }
        recordDiagnostic("通知回复：会话 \(sessionId)，\(text.count) 字")
        let background = UIApplication.shared.beginBackgroundTask(withName: "dsh-notification-reply")
        defer {
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
        }

        if !connection.isConnected {
            if let saved = UserDefaults.standard.string(forKey: Self.savedServerAddressKey), !saved.isEmpty {
                connection.serverAddress = saved
            }
            if connection.pin.isEmpty, let savedPin = PinKeychain.load() {
                connection.pin = savedPin
            }
            if connection.pin.isEmpty {
                recordDiagnostic("通知回复失败：未连接且没有可用密码")
                return
            }
            await connect()
            guard connection.isConnected else {
                recordDiagnostic("通知回复失败：自动重连未成功")
                return
            }
        }

        // 通知回复一律排队：列表里的 running 可能滞后，误打断比晚一轮更糟。
        let mode = PromptPolicy.replyMode(
            isRunning: sessionStore.sessions.first { $0.sessionId == sessionId }?.running ?? false
        ).rawValue
        let requestId = UUID().uuidString.lowercased()
        do {
            _ = try await rpcClient.rpcWithRetryAdapted("session/prompt", args: ["request": [
                "requestId": requestId,
                "sessionId": sessionId,
                "mode": mode,
                "content": [["type": "text", "text": text]],
                "clientTimeZone": TimeZone.current.identifier
            ]])
            ackedSendRpcIds.insert(requestId)
            addOutbox(sessionId: sessionId, rpcId: requestId, text: text)
            clearFinishedAwaiting(sessionId)
            recordDiagnostic("通知回复已发送（模式 \(mode)）")
        } catch {
            recordDiagnostic("通知回复发送失败：\(error.localizedDescription)")
        }
    }

    /// 从通知点进来：确保已连接，然后打开对应会话。
    @MainActor
    func openSessionFromNotification(sessionId: String) async {
        // 无前置条件
        if !connection.isConnected {
            if connection.pin.isEmpty, let savedPin = PinKeychain.load() {
                connection.pin = savedPin
            }
            if connection.pin.isEmpty, let saved = UserDefaults.standard.string(forKey: Self.savedServerAddressKey), !saved.isEmpty {
                connection.serverAddress = saved
            }
            await connect()
        }
        guard sessionStore.sessions.contains(where: { $0.sessionId == sessionId }) else {
            recordDiagnostic("通知打开会话失败：找不到 \(sessionId)")
            return
        }
        clearFinishedAwaiting(sessionId)
        openSession(sessionId)
    }
}
