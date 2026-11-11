// PocketMessage

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


struct PocketMessage: Identifiable {
    let id: String
    let sequence: Int
    let kind: String
    let text: String
    let isUser: Bool
    let isPending: Bool
    /// 待发消息在会话里的显示排序位置（发送时刻最后一条已确认消息的 sequence）。
    var localSortKey: Int? = nil
    let images: [PocketImageRef]
    let localImages: [UIImage]
    /// 发送时客户端生成的 requestId，服务端会回填到 user/message 的 source.rpcId，用来精确对账。
    /// 注意：服务端返回的 rpcId 是**小写 UUID**，客户端统一小写后再比较，避免大小写不一致。
    let rpcId: String?

    init(demoText: String, isUser: Bool, sequence: Int, localImages: [UIImage] = []) {
        self.id = "demo-\(sequence)"
        self.sequence = sequence
        self.kind = isUser ? "user/message" : "assistant/message"
        self.text = demoText
        self.isUser = isUser
        self.isPending = false
        self.images = []
        self.localImages = localImages
        self.rpcId = nil
    }

    init(pendingText: String, localImages: [UIImage] = [], rpcId: String? = nil, sortSequence: Int? = nil) {
        self.id = "pending-\(UUID().uuidString)"
        self.sequence = Int.max
        self.localSortKey = sortSequence
        self.kind = "user/message"
        self.text = pendingText
        self.isUser = true
        self.isPending = true
        self.images = []
        self.localImages = localImages
        self.rpcId = RPCId.normalized(rpcId)
    }

    init(sequence: Int, kind: String, text: String, isUser: Bool,
         rpcId: String?, images: [PocketImageRef]) {
        self.id = "event-\(sequence)"
        self.sequence = sequence
        self.kind = kind
        self.text = text
        self.isUser = isUser
        self.isPending = false
        self.images = images
        self.localImages = []
        self.rpcId = RPCId.normalized(rpcId)
    }

    init?(record: [String: Any]) {
        guard let event = record["event"] as? [String: Any] else { return nil }
        self.init(event: event)
    }

    init?(event: [String: Any]) {
        guard let kind = event["type"] as? String,
              ["user/message", "assistant/message"].contains(kind),
              let sequence = (event["seq"] as? NSNumber)?.intValue,
              let data = event["data"] as? [String: Any] else { return nil }
        let message = (data["message"] as? [String: Any]) ?? data
        // DSH also stores injected runtime context as user/message events. Those
        // are model inputs, not messages the human sent, and must stay out of chat UI.
        let source = (message["source"] as? [String: Any]) ?? (data["source"] as? [String: Any])
        if kind == "user/message" {
            guard source?["kind"] as? String == "user" else { return nil }
        }
        let content = message["content"] as? [[String: Any]] ?? []
        let text = content.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }.joined()
        let images = content.compactMap { block -> PocketImageRef? in
            guard block["type"] as? String == "image",
                  let attachment = block["attachment"] as? [String: Any] else { return nil }
            return PocketImageRef(json: attachment)
        }
        guard !text.isEmpty || !images.isEmpty else { return nil }
        self.id = "event-\(sequence)"
        self.sequence = sequence
        self.kind = kind
        self.text = text
        self.isUser = kind == "user/message"
        self.isPending = false
        self.images = images
        self.localImages = []
        self.rpcId = RPCId.normalized(source?["rpcId"] as? String)
    }
}
