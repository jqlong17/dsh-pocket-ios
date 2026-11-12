// 诊断值类型

import Foundation

/// 诊断用的两个纯展示类型：会话进出记录与内存采样。
///
/// 放在独立文件而不是 ConnectionModel 里：它们是**值类型、无依赖**，
/// 与模型的生命周期无关；模型文件只放属性与转发（spec/12）。

struct DiagnosticVisit {
    var index: Int
    var enterMs: Int?
    var leaveMs: Int?
    var reusedMessages: Int
    var memoryEnter: Int
    var memoryLeave: Int?
    var viewsAfterLeave: Int?

    var line: String {
        let enter = enterMs.map { "进 \($0)ms" } ?? "进 …"
        let leave = leaveMs.map { "出 \($0)ms" } ?? "出 —"
        let views = viewsAfterLeave.map { "页 \($0)" } ?? "页 …"
        let left = memoryLeave.map(String.init) ?? "—"
        return "\(index)  \(enter) 复用\(reusedMessages)条  \(leave)  \(views)  内存 \(memoryEnter)→\(left)"
    }
}

struct DiagnosticSample {
    var at: Date
    var memoryMB: Int
    var pending: Int
    var queued: Int
    var failed: Int
    var network: String
    var enterMs: Int?

    var line: String {
        let clock = Self.clock.string(from: at)
        var text = "\(clock)  内存 \(memoryMB)  待确认 \(pending)  断网 \(queued)  失败 \(failed)  网络 \(network)"
        if let enterMs {
            text += "  进入 \(enterMs) ms"
        }
        return text
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

/// 诊断索引用的会话规模快照（纯数据，无依赖）。
struct ConversationSizeSnapshot {
    var title: String
    var messages: Int
    var userMessages: Int
    var assistantMessages: Int
    var pendingMessages: Int
    var steps: Int
    var unfinishedSteps: Int
    var errorSteps: Int
    var stepGroups: Int
    var failures: Int
    var timelineRows: Int
    var messageBytes: Int
    var stepBytes: Int
    var images: Int
    var cachedImages: Int
    var cachedImageBytes: Int
    var liveViews: Int
    var hasMore: Bool
    var loadMs: Int?
    var loadSource: String?
    var memoryMB: String
}
