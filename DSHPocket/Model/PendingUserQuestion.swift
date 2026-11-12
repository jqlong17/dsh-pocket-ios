// PendingUserQuestion

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


/// 桌面端 `ask_user_question` 正在等待用户选择的问题。
struct PendingUserQuestion: Equatable {
    struct Option: Identifiable, Equatable {
        let label: String
        let description: String?
        var id: String { label }
    }
    struct Item: Identifiable, Equatable {
        let id: String
        let header: String?
        let question: String
        let detail: String?
        let options: [Option]
        let multiSelect: Bool
    }
    let callId: String
    let questions: [Item]
}

extension PendingUserQuestion {
    /// 从 DSHKit 的解析结果构造（解析与类型转换分离，见 spec/12）。
    init(payload: PendingQuestionPayload) {
        self.init(callId: payload.callId,
                  questions: payload.questions.map { item in
                      Item(id: item.id,
                           header: item.header,
                           question: item.question,
                           detail: item.detail,
                           options: item.options.map { Option(label: $0.label, description: $0.description) },
                           multiSelect: item.multiSelect)
                  })
    }
}
