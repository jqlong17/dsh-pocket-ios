// DraftStore

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


/// 按会话保存输入框草稿（退出/切换会话后回来还能接着写）。
enum DraftStore {
    private static let key = "dsh-pocket.drafts"

    private static func loadAll() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    static func draft(for sessionId: String) -> String {
        loadAll()[sessionId] ?? ""
    }

    static func save(_ draft: String, for sessionId: String) {
        var all = loadAll()
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            all.removeValue(forKey: sessionId)
        } else {
            all[sessionId] = draft
            // 控制数量，避免无限增长。
            if all.count > 50 {
                all = Dictionary(all.sorted { $0.key < $1.key }.suffix(50), uniquingKeysWith: { a, _ in a })
            }
        }
        UserDefaults.standard.set(all, forKey: key)
    }
}
