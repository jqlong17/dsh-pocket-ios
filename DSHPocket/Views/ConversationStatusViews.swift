// ConversationStatusViews

import SwiftUI

/// 对话页顶部的状态条：错误提示、演示模式/连接状态。
///
/// 纯展示，只有「重连」一个动作回调；拆出来是为了让 ConversationView 只留消息区与滚动逻辑。
struct ConversationStatusBanner: View {
    @Bindable var model: ConnectionModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.conversationError {
                Text(error).font(.footnote).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.red.opacity(0.06))
            }
            if showsBanner {
                HStack(spacing: 6) {
                    if model.isDemoMode {
                        Image(systemName: "play.circle").font(.caption2).foregroundStyle(.secondary)
                        Text(L10n.t("演示模式 · 示例数据，未连接电脑")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        Circle().fill(liveStateColor(model.liveConnection)).frame(width: 6, height: 6)
                        Text(model.liveConnection.label).font(.caption2).foregroundStyle(.secondary)
                        if model.liveConnection.isDisconnected {
                            Button(L10n.t("重连")) { model.manualReconnect() }
                                .font(.caption2.weight(.semibold))
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal).padding(.vertical, 4)
                .transition(.opacity)
            }
        }
    }

    private var showsBanner: Bool {
        #if DEBUG
        let demo = model.isDemoMode && !DebugLaunch.hideDemoBanner
        #else
        let demo = model.isDemoMode
        #endif
        return demo || (!model.isDemoMode && model.liveConnection != .connected)
    }

    private func liveStateColor(_ state: LiveConnectionState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected: return .red
        case .idle, .demo: return .gray
        }
    }
}

/// 输入栏上方的活动区：待回答问题卡、生成中状态（含停止）、补发进度。
struct ConversationActivityBar: View {
    @Bindable var model: ConnectionModel

    var body: some View {
        VStack(spacing: 0) {
            if let question = model.pendingQuestion {
                UserQuestionCard(request: question, model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if model.isTurnRunning {
                // 生成状态放在输入栏上方左侧：等待时视线就在这里。
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("\(L10n.t("深度求索中")) · \(elapsed(since: model.turnStartedAt, now: context.date))")
                            .font(.caption)
                            .foregroundStyle(PocketChrome.brandText)
                            .monospacedDigit()
                    }
                    Spacer()
                    Button { Task { await model.cancelTurn() } } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.circle.fill")
                            Text(L10n.t("停止"))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("停止生成")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .background(.background)
            }
            if let note = model.outbox.flushNote {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text(note).font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private extension ConversationActivityBar {
    /// 「深度求索中 · 1 分 56 秒」里的时长。
    func elapsed(since start: Date?, now: Date) -> String {
        guard let start else { return "计算中" }
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return seconds < 60 ? "\(seconds) 秒" : "\(seconds / 60) 分 \(seconds % 60) 秒"
    }
}
