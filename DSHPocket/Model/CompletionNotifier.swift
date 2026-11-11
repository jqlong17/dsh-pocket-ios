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

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(sessionId: String, title: String) {
        let content = UNMutableNotificationContent()
        content.title = "对话已完成"
        content.body = title.isEmpty ? "等待你的回复" : "「\(title)」等待你的回复"
        content.sound = .default
        content.categoryIdentifier = Self.replyCategoryID
        content.threadIdentifier = sessionId
        content.userInfo = [Self.sessionIdKey: sessionId, "title": title]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
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
