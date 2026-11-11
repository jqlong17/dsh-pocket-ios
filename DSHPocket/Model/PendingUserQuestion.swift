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
