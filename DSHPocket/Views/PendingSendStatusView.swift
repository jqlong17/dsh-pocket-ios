// PendingSendStatusView

import SwiftUI
import DSHKit

/// 待确认消息下方的一行状态与动作：发送中 / 已发出 / 失败 / 待联网。
///
/// 从 `MessageRow` 抽出（2026-11-25）：这一行的文案和动作（重发、删除失败消息）
/// 是一个独立职责，也让 `MessageRow` 保持在架构检查的行数阈值内。
struct PendingSendStatusView: View {
    let message: PocketMessage
    @Bindable var model: ConnectionModel
    let state: PendingSendState
    /// 删除是破坏性且不可恢复的，必须先确认（HIG action sheets）。
    @State private var confirmingDiscard = false

    var body: some View {
        HStack(spacing: 5) {
            switch state {
            case .sending:
                ProgressView().scaleEffect(0.55).frame(width: 11, height: 11)
                Text(L10n.t("发送中…"))
            case .acked(let steered):
                Image(systemName: steered ? "arrow.triangle.branch" : "clock").font(.caption2)
                Text(steered ? L10n.t("已引导，正在继续") : L10n.t("已发出，等待处理"))
            case .failed:
                Image(systemName: "exclamationmark.circle").font(.caption2)
                Text(L10n.t("发送失败"))
                Button(L10n.t("重新发送")) { model.retryPendingMessage(message) }
                    .buttonStyle(.borderless)
                    .font(.caption2.weight(.semibold))
                    .accessibilityIdentifier("pending-resend")
                Button(L10n.t("删除"), role: .destructive) { confirmingDiscard = true }
                    .buttonStyle(.borderless)
                    .font(.caption2.weight(.semibold))
                    .accessibilityLabel(L10n.t("删除这条发送失败的消息"))
                    .accessibilityIdentifier("pending-delete")
            case .queued:
                Image(systemName: "wifi.slash").font(.caption2)
                Text(L10n.t("等待联网后一并发送"))
            }
        }
        .font(.caption2)
        .foregroundStyle(stateColor)
        .padding(.horizontal, 4)
        .alert(L10n.t("删除这条发送失败的消息？"), isPresented: $confirmingDiscard) {
            Button(L10n.t("删除"), role: .destructive) {
                model.discardFailedMessage(message)
            }
            Button(L10n.t("取消"), role: .cancel) {}
        } message: {
            Text(L10n.t("消息没有发出，删除后无法恢复。"))
        }
    }

    private var stateColor: Color {
        switch state {
        case .failed: return Color.red.opacity(0.85)
        case .queued: return Color.orange
        default: return Color.secondary
        }
    }
}
