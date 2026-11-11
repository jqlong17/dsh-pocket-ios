// PocketSession

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


struct PocketSession: Identifiable, Hashable {
    let sessionId: String
    let updatedAt: TimeInterval
    let running: Bool
    let blank: Bool
    let title: String?
    let cwd: String?
    let origin: String?
    let parentSessionId: String?
    var id: String { sessionId }

    init(sessionId: String, updatedAt: TimeInterval, running: Bool, blank: Bool, title: String? = nil, cwd: String? = nil, origin: String? = nil, parentSessionId: String? = nil) {
        self.sessionId = sessionId
        self.updatedAt = updatedAt
        self.running = running
        self.blank = blank
        self.title = title
        self.cwd = cwd
        self.origin = origin
        self.parentSessionId = parentSessionId
    }

    init?(json: [String: Any]) {
        guard let id = json["sessionId"] as? String else { return nil }
        let projection = json["projections"] as? [String: Any]
        let values = projection?["values"] as? [String: Any]
        let title = values?["title"] as? String
        self.init(sessionId: id, updatedAt: json["updatedAt"] as? TimeInterval ?? 0,
                  running: json["running"] as? Bool ?? false, blank: json["blank"] as? Bool ?? false,
                  title: title, cwd: json["cwd"] as? String,
                  origin: json["origin"] as? String, parentSessionId: json["parentSessionId"] as? String)
    }

    func withTitle(_ title: String) -> PocketSession {
        PocketSession(sessionId: sessionId, updatedAt: updatedAt, running: running, blank: blank,
                      title: title, cwd: cwd, origin: origin, parentSessionId: parentSessionId)
    }

    /// DSH 桌面端侧边栏不显示 subagent 子会话和空会话，iOS 保持同样的可见性规则。
    var isSubagent: Bool { origin == "subagent" || parentSessionId != nil }
    var isHiddenFromList: Bool { blank || (title?.isEmpty ?? true) }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if blank { return "新会话" }
        if let cwd {
            let name = URL(fileURLWithPath: cwd).lastPathComponent
            if !name.isEmpty { return name }
        }
        return "未命名会话"
    }
}
