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


/// 本地发件箱：未确认的正文一直留在磁盘上，直到服务端历史确认，或用户取消发送。
/// 断网暂存用 `heldOffline` 标记，不按时间删除；联网后按写入顺序一并补发。
struct OutboxEntry: Codable, Identifiable {
    let id: String          // = 发送时生成的 rpcId
    let sessionId: String
    let text: String
    let createdAt: Double
    /// 断网时已点发送：等联网后一并发出。旧数据没有这个字段，解码为 false。
    var heldOffline: Bool
    /// 补发或发送遇到非网络错误。正文仍在，打开会话后可以重发。旧数据解码为 false。
    var sendFailed: Bool
    /// 服务端已经收下这次 prompt，但历史里还没出现对应消息。旧数据解码为 false。
    var accepted: Bool

    init(id: String, sessionId: String, text: String, createdAt: Double,
         heldOffline: Bool = false, sendFailed: Bool = false, accepted: Bool = false) {
        self.id = id
        self.sessionId = sessionId
        self.text = text
        self.createdAt = createdAt
        self.heldOffline = heldOffline
        self.sendFailed = sendFailed
        self.accepted = accepted
    }

    enum CodingKeys: String, CodingKey {
        case id, sessionId, text, createdAt, heldOffline, sendFailed, accepted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Double.self, forKey: .createdAt)
        heldOffline = try container.decodeIfPresent(Bool.self, forKey: .heldOffline) ?? false
        sendFailed = try container.decodeIfPresent(Bool.self, forKey: .sendFailed) ?? false
        accepted = try container.decodeIfPresent(Bool.self, forKey: .accepted) ?? false
    }
}
