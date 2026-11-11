// OutboxEntry

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


/// 本地发件箱：消息已发出但服务端还没落成 user/message 事件时，保持可见，避免"消息丢了"的错觉。
struct OutboxEntry: Codable, Identifiable {
    let id: String          // = 发送时生成的 rpcId
    let sessionId: String
    let text: String
    let createdAt: Double
}
