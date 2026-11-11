// TurnFailureNotice

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


/// 一轮失败的原因，插在对应对话后面。
struct TurnFailureNotice: Identifiable, Equatable {
    let sequence: Int
    let message: String
    let code: String?
    var id: String { "turn-fail-\(sequence)" }

    /// 桌面端那行红字的短说法。长英文和 request_id 不直接铺开。
    var displayText: String {
        if code == "MODEL_SWITCH_COMPACTION_FAILED"
            || message.localizedCaseInsensitiveContains("compaction failed") {
            return L10n.t("切换模型失败：上下文压缩没有完成，额度不足。")
        }
        if code == "ACCOUNT_QUOTA" || message.localizedCaseInsensitiveContains("Insufficient Balance") {
            return L10n.t("当前请求的额度已用尽")
        }
        if let range = message.range(of: " (request_id:") {
            return String(message[..<range.lowerBound])
        }
        return message
    }
}
