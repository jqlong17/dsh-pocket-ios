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
        // 在「发起注册」处就打点：如果回调永远不来，这个时间戳能证明
        // 「我们确实调过」——否则分不清「没调用」和「调了没回调」。
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "dsh-pocket.apns-attempt-at")
        recordDiagnostic("APNs 注册已发起")
        UIApplication.shared.registerForRemoteNotifications()
        guard let token = pushToken, connection.isConnected else { return }
        // 直接打插件端点，**不能用 rpcAdapted**：
        // 它拼的是 `api/<method>`（DSH 内核的 RPC），而 push.register 是本插件在
        // `/dsh-pocket-ios/` 下的端点——之前一直 404，token 永远注册不上。
        do {
            let ok = try await postPluginEndpoint(
                "push.register",
                body: [
                    "token": token,
                    "environment": "sandbox",
                    "bundleId": Bundle.main.bundleIdentifier ?? "",
                    "deviceName": UIDevice.current.name,
                ]
            )
            recordDiagnostic(ok ? "APNs token 已注册（\(token.suffix(6))）" : "APNs token 注册被拒")
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
            // 通知回复只发纯文本，字段仍写全，方便和另外两条日志用同一套解析。
            DiagFileLog.log("send from=iOS(notification) chars=\(text.count) images=0 hasImage=false session=\(shortSessionId(sessionId))")
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


    /// POST 到本插件自己的端点（`/dsh-pocket-ios/<name>`），返回是否 2xx。
    ///
    /// 为什么不复用 `rpcAdapted`：它固定拼 `api/<method>`，那是 DSH 内核的命名空间；
    /// 插件端点必须走 `/dsh-pocket-ios/` 前缀（与 telemetry 同一套路）。
    @MainActor
    func postPluginEndpoint(_ name: String, body: [String: Any]) async throws -> Bool {
        guard let base = try? Self.serverURL(from: connection.serverAddress) else { return false }
        // 不能用 appendingPathComponent：它会把路径里的 `/` 编码成 `%2F`，
        // 请求变成 `/dsh-pocket-ios%2Fpush.register`，必然 404。
        let baseString = base.absoluteString.hasSuffix("/")
            ? String(base.absoluteString.dropLast())
            : base.absoluteString
        guard let url = URL(string: baseString + "/dsh-pocket-ios/" + name) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            UserDefaults.standard.set("no-http-response", forKey: "dsh-pocket.push-register-error")
            return false
        }
        if (200..<300).contains(http.statusCode) {
            UserDefaults.standard.removeObject(forKey: "dsh-pocket.push-register-error")
            return true
        }
        let body = String(data: data.prefix(120), encoding: .utf8) ?? ""
        UserDefaults.standard.set(
            "HTTP \(http.statusCode) \(body)",
            forKey: "dsh-pocket.push-register-error"
        )
        return false
    }

}
