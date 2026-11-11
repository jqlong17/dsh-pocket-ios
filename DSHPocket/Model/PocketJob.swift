// PocketJob

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


/// 一个后台任务（对应 DSH 的 `JobView`）。
struct PocketJob: Identifiable, Equatable {
    let id: String
    let kind: String
    let label: String
    let status: String
    let startedAt: Double
    let finishedAt: Double?
    let progress: String?
    let detail: String?

    var isRunning: Bool { status == "running" || status == "stopping" }

    /// 只给看人看的名字，不露出裸 jobId。
    var kindLabel: String {
        switch kind {
        case "bash", "shell", "exec": return L10n.t("命令")
        case "workflow": return L10n.t("工作流")
        case "subagent", "agent": return L10n.t("子任务")
        case "tool": return L10n.t("工具")
        case "script": return L10n.t("脚本")
        case "test": return L10n.t("测试")
        default: return kind.isEmpty ? L10n.t("任务") : kind
        }
    }

    /// 标题：优先用任务自带的 label，没有就用类型名 + 短序号。
    var displayName: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let short = id.split(separator: "-").last.map(String.init) ?? ""
        return short.isEmpty ? kindLabel : "\(kindLabel) · \(short.prefix(4))"
    }

    var startedLabel: String {
        guard startedAt > 0 else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: startedAt / 1000))
    }

    var statusLabel: String {
        switch status {
        case "running": return L10n.t("正在运行")
        case "stopping": return L10n.t("正在停止")
        case "completed": return L10n.t("已完成")
        case "killed": return L10n.t("已停止")
        case "failed": return L10n.t("失败")
        default: return status
        }
    }

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String else { return nil }
        self.id = id
        self.kind = json["kind"] as? String ?? ""
        self.label = json["label"] as? String ?? ""
        self.status = json["status"] as? String ?? ""
        self.startedAt = (json["startedAt"] as? NSNumber)?.doubleValue ?? 0
        self.finishedAt = (json["finishedAt"] as? NSNumber)?.doubleValue
        self.progress = json["progress"] as? String
        self.detail = json["detail"] as? String
    }
}
