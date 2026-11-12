// ConnectionValueTypes

import Foundation

/// 连接状态与发送核验结果：纯值类型，无依赖，从 ConnectionModel 里外移。
///
/// 放在独立文件的原因：它们与模型生命周期无关，视图与测试都可以直接引用；
/// 也让 ConnectionModel.swift 只留属性与编排（spec/12）。

enum LiveConnectionState: Equatable {
    case idle
    case demo
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case disconnected(reason: String?)

    var label: String {
        switch self {
        case .idle: return L10n.t("未连接")
        case .demo: return L10n.t("演示模式")
        case .connecting: return L10n.t("正在连接")
        case .connected: return L10n.t("已连接")
        case .reconnecting(let attempt): return attempt > 1 ? L10n.tf("重连中（第 %d 次）", attempt) : L10n.t("正在重连")
        case .disconnected: return L10n.t("已断开")
        }
    }

    /// 诊断报告用的稳定英文标识：报告固定英文，且要与 `State connected` 的小写风格一致。
    /// 不要用 `label`——它是本地化的，中文环境下会输出「已连接」。
    var reportLabel: String {
        switch self {
        case .idle: return "idle"
        case .demo: return "demo"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reconnecting(let attempt):
            return attempt > 1 ? "reconnecting (attempt \(attempt))" : "reconnecting"
        case .disconnected(let reason):
            return reason.map { "disconnected (\($0))" } ?? "disconnected"
        }
    }

    var isConnected: Bool { self == .connected }
    var isDisconnected: Bool { if case .disconnected = self { return true }; return false }
}

enum SendVerification {
    case landed
    case absent        // 请求成功但历史里确实没有这条消息
    case unreachable   // 网络失败，无法判断——不能当作失败提示用户
}

struct PendingQuote: Identifiable, Equatable {
    let id: String
    let sequence: Int
    let sender: String
    let text: String
}

enum PendingSendState { case sending, acked(steered: Bool), failed, queued }

/// 模型选择器的值类型（从 ConnectionModel 嵌套类型外移）。
struct ModelOption: Identifiable, Hashable {
    let provider: String
    let model: String
    let name: String
    var id: String { "\(provider)/\(model)" }
}

struct ModelGroup: Identifiable {
    let id: String
    let name: String
    let models: [ModelOption]
}
