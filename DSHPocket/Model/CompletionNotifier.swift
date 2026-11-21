// CompletionNotifier

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


/// 会话完成提醒：本地通知（前台也会弹 banner + 声音），支持在通知/Apple Watch 上直接文字回复。
final class CompletionNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CompletionNotifier()

    static let replyCategoryID = "DSH_REPLY"
    static let replyActionID = "DSH_REPLY_ACTION"
    static let sessionIdKey = "sessionId"

    /// 由 ConnectionModel 注入：收到通知回复时把文本发回对应会话。
    var onReply: ((String, String) async -> Void)?
    /// 由 ConnectionModel 注入：点击通知打开对应会话。
    var onOpenSession: ((String) -> Void)?

    private var configured = false
    /// 授权请求只发一次。`requestAuthorization` 弹的是系统框，
    /// 不能在启动时静默弹（用户还没做任何操作就被打断），所以改成「首次真要发通知时才问」。
    private var didRequestPermission = false

    func configure() {
        guard !configured else { return }
        configured = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // 通知展开/Apple Watch 上会出现「回复」输入框。
        let reply = UNTextInputNotificationAction(
            identifier: Self.replyActionID,
            title: "回复",
            options: [],
            textInputButtonTitle: "发送",
            textInputPlaceholder: "回复 DSH…"
        )
        let category = UNNotificationCategory(
            identifier: Self.replyCategoryID,
            actions: [reply],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// 请求通知授权（幂等）。
    ///
    /// **不要**在 App 启动时调用：`ConnectionModel.init` 里原本无条件调它，
    /// 结果每次冷启动都会加载 UserNotifications 并弹系统授权框——用户还没做任何操作。
    /// 现在改成由「首次真正需要发通知」触发（见 `notify`）或用户主动开启开关时触发。
    func requestPermission() {
        guard !didRequestPermission else { return }
        didRequestPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// - Parameters:
    ///   - title: 会话标题
    ///   - preview: AI 回复的开头几句（空则只显示标题）
    func notify(sessionId: String, title: String, preview: String = "") {
        // 首次要发通知时才问授权：这时候用户已经用起来了，弹框有上下文。
        requestPermission()
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "对话已完成" : title
        // 正文优先显示「AI 说了什么」——用户真正想知道的是内容，而不是「完成了」这件事。
        let trimmedPreview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPreview.isEmpty {
            content.body = trimmedPreview
        } else {
            content.body = title.isEmpty ? "等待你的回复" : "「\(title)」等待你的回复"
        }
        content.sound = .default
        content.categoryIdentifier = Self.replyCategoryID
        content.threadIdentifier = sessionId
        content.userInfo = [Self.sessionIdKey: sessionId, "title": title]
        // **用 sessionId 当 identifier**：同一会话的新通知会替换旧的。
        // 之前用 UUID，同一会话每完成一次就多一条，实测一小时内堆了 5 条一模一样的。
        let request = UNNotificationRequest(identifier: sessionId, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// 把 Markdown 正文压成「适合通知栏的一行字」。
    ///
    /// 通知栏不渲染 Markdown，保留 `**`/`#`/`|` 这些记号只会显得脏；
    /// 代码块整段丢弃（读者在锁屏上也不需要看代码）。
    static func previewText(_ raw: String, limit: Int) -> String {
        var lines = raw.components(separatedBy: "\n")
        var inCode = false
        var kept: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inCode.toggle(); continue }
            if inCode { continue }
            if trimmed.isEmpty { continue }
            kept.append(trimmed)
        }
        var text = kept.joined(separator: " ")
        for token in ["**", "__", "`", "##", "# ", "> "] {
            text = text.replacingOccurrences(of: token, with: "")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > limit {
            text = String(text.prefix(limit)) + "…"
        }
        return text
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // 前台一律不弹：用户正在用 App，横幅和提示音都是打扰。
        // 插件侧还有 push.visible 抑制作为第二道闸，两边任一命中都不该打扰。
        []
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let sessionId = response.notification.request.content.userInfo[Self.sessionIdKey] as? String,
           !sessionId.isEmpty {
            onOpenSession?(sessionId)
            completionHandler()
            return
        }
        guard response.actionIdentifier == Self.replyActionID,
              let textResponse = response as? UNTextInputNotificationResponse else {
            completionHandler()
            return
        }
        let text = textResponse.userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let sessionId = response.notification.request.content.userInfo[Self.sessionIdKey] as? String,
              !sessionId.isEmpty else {
            completionHandler()
            return
        }
        Task { @MainActor in
            await self.onReply?(sessionId, text)
            completionHandler()
        }
    }
}
