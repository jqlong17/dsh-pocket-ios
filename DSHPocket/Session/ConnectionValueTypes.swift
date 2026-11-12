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

    var isConnected: Bool { self == .connected }
    var isDisconnected: Bool { if case .disconnected = self { return true }; return false }
}

enum SendVerification {
    case landed
    case absent        // 请求成功但历史里确实没有这条消息
    case unreachable   // 网络失败，无法判断——不能当作失败提示用户
}
