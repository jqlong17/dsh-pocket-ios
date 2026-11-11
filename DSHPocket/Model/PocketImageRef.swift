// PocketImageRef

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


/// 一张已落到电脑端附件库的图片引用（会话历史 / 工具结果里的图片）。
struct PocketImageRef: Identifiable, Hashable {
    init(attachmentId: String, mediaType: String? = nil, bytes: Int = 0, width: Int? = nil,
         height: Int? = nil, name: String? = nil) {
        self.attachmentId = attachmentId
        self.mediaType = mediaType ?? "image/jpeg"
        self.bytes = bytes
        self.width = width ?? 0
        self.height = height ?? 0
        self.name = name
    }

    let attachmentId: String
    let mediaType: String
    let bytes: Int
    let width: Int
    let height: Int
    let name: String?
    var id: String { attachmentId }

    init?(json: [String: Any]) {
        guard let attachmentId = json["attachmentId"] as? String else { return nil }
        self.attachmentId = attachmentId
        self.mediaType = json["mediaType"] as? String ?? "image/jpeg"
        self.bytes = (json["bytes"] as? NSNumber)?.intValue ?? 0
        self.width = (json["width"] as? NSNumber)?.intValue ?? 0
        self.height = (json["height"] as? NSNumber)?.intValue ?? 0
        self.name = json["name"] as? String
    }

    var requestJSON: [String: Any] {
        var value: [String: Any] = ["attachmentId": attachmentId, "mediaType": mediaType]
        if bytes > 0 { value["bytes"] = bytes }
        if width > 0 { value["width"] = width }
        if height > 0 { value["height"] = height }
        if let name, !name.isEmpty { value["name"] = name }
        return value
    }
}
