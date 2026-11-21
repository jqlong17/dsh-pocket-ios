// AppSettingsSheet

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


struct AppSettingsSheet: View {
    @Bindable var model: ConnectionModel
    @AppStorage("dsh-pocket.session-list-mode") private var sessionListModeRaw = SessionListMode.grouped.rawValue
    /// 复制诊断后的短暂反馈：按钮图标从听诊器变成对勾。
    /// 放在设置里而不是会话页，是因为连不上时根本没有会话可进——
    /// 而「连不上」恰恰是最需要诊断的时候（2026-11-15 用户反馈）。
    @State private var diagnosticsCopied = false
    @State private var showingDisconnectConfirm = false
    @Environment(\.dismiss) private var dismiss
    @State private var languageRevision = 0
    /// 排序面板的上下文。用 item 而不是「bool + 数据」两个状态：
    /// 后者弹窗时读到的数据可能还是上一轮的空数组（SwiftUI 同一更新周期批量处理，
    /// 附件图黑屏那次也是这个原因）。
    @State private var reorderContext: ReorderContext?
    /// 连接健康探测：哪条地址现在能用、多快。
    @State private var probeRunner = EndpointProbeRunner()

    struct ReorderContext: Identifiable {
        let id = UUID()
        let workspaces: [PocketWorkspace]
        let failure: String?
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("语言")) {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            LanguageStore.shared.code = language
                        } label: {
                            HStack {
                                Text(language.title())
                                Spacer()
                                if LanguageStore.shared.code == language {
                                    Image(systemName: "checkmark").foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37))
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section(L10n.t("会话列表")) {
                    Picker(L10n.t("显示方式"), selection: $sessionListModeRaw) {
                        ForEach(SessionListMode.allCases) { mode in
                            Text(mode.title()).tag(mode.rawValue)
                        }
                    }
                }
                Section(L10n.t("工作区")) {
                    Button {
                        openReorder()
                    } label: {
                        HStack {
                            Text(L10n.t("调整工作区顺序"))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                Section(L10n.t("完成提醒")) {
                    Toggle(isOn: Binding(
                        get: { model.completionAlertsEnabled },
                        set: { _ in model.toggleCompletionAlerts() }
                    )) {
                        Text(L10n.t("完成提醒"))
                    }
                }
                Section {
                    Picker(selection: Binding(
                        get: { model.busyEnterPreference },
                        set: { mode in
                            Task { await model.setBusyEnterPreference(mode) }
                        }
                    )) {
                        Text(L10n.t("插话发送")).tag(PromptMode.steer)
                        Text(L10n.t("排队发送")).tag(PromptMode.queue)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("繁忙时的发送行为"))
                            Text(L10n.t("智能体运行时按下发送键的投递方式"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(L10n.t("发送"))
                } footer: {
                    Text(L10n.t("与电脑端共用同一份设置。空闲时总是新开一轮，此设置只在生成中生效。"))
                }

                Section(L10n.t("调试")) {
                    Button {
                        UIPasteboard.general.string = model.diagnosticReport()
                        diagnosticsCopied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            diagnosticsCopied = false
                        }
                    } label: {
                        Label(diagnosticsCopied ? L10n.t("已复制诊断信息") : L10n.t("复制诊断信息"),
                              systemImage: diagnosticsCopied ? "checkmark.circle.fill" : "stethoscope")
                    }
                    Button {
                        Task { await model.diagnoseBusyEnterWrite() }
                    } label: {
                        Label(L10n.t("诊断发送方式写入"), systemImage: "stethoscope")
                    }
                    Toggle(isOn: Binding(
                        get: { LayoutDebug.enabled },
                        set: { LayoutDebug.enabled = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("布局调试模式"))
                            Text(L10n.t("给关键组件画红框并标编号，方便沟通间距"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: Binding(
                        get: { model.probeRunner.testMode },
                        set: { model.probeRunner.testMode = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("连接探测测试模式"))
                            Text(L10n.t("每 10 秒探测一次（默认 60 秒），用于排查连接问题"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                // 一键切换：列出这台设备连过的地址，点一下直接连。
                //
                // 复用 ConnectionVault 按地址隔离的设备凭证，所以切回以前连过的
                // 电脑通常不需要再输密码——「点一下就回去」才是历史连接的意义。
                if !model.savedEndpoints.isEmpty {
                    Section {
                        ForEach(model.savedEndpoints) { endpoint in
                            Button {
                                model.connection.serverAddress = endpoint.address
                                model.connection.errorMessage = nil
                                Task { await model.connect() }
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(endpoint.displayName)
                                            .foregroundStyle(.primary)
                                        Text(endpoint.address)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer(minLength: 8)
                                    Sparkline(series: model.probeLatency[endpoint.address])
                                        .frame(width: 52, height: 14)
                                    healthBadge(for: endpoint.address)
                                    if endpoint.address == model.connection.serverAddress {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(L10n.t("切换连接"))
                    } footer: {
                        Text(L10n.t("点一下直接切换；连过的地址已记住凭证，不用再输密码。"))
                    }
                }

                // 当前连接一览：方式 / 状态 / 地址。
                // 放在「断开连接」上方，因为断开前最该确认的就是「我现在连的是哪条路」。
                Section {
                    LabeledContent(L10n.t("连接方式")) {
                        Text(connectionKindLabel)
                    }
                    LabeledContent(L10n.t("状态")) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(connectionStatusColor)
                                .frame(width: 8, height: 8)
                            // 用 isConnected（HTTP 已连）而不是 liveConnection（实时流）：
                            // 后者要等用户点进某个会话才开始，停在设置页时会一直显示「未连接」，
                            // 明明会话列表都已经拉到了（实测：点切换后 HTTP 通，UI 仍显示未连接）。
                            Text(model.connection.isConnected ? L10n.t("已连接") : model.liveConnectionState)
                        }
                    }
                    LabeledContent(L10n.t("地址")) {
                        Text(model.connection.serverAddress)
                            .font(.footnote)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    LabeledContent(L10n.t("稳定性")) {
                        HStack(spacing: 6) {
                            Sparkline(series: model.probeLatency[model.connection.serverAddress])
                                .frame(width: 46, height: 14)
                            Circle()
                                .fill(stability.color)
                                .frame(width: 8, height: 8)
                            Text(stability.label)
                        }
                    }
                } header: {
                    Text(L10n.t("当前连接"))
                }

                // 连接操作从会话列表左上角移到这里：那里只留高频动作（新建会话）。
                Section {
                    Button(role: .destructive) {
                        showingDisconnectConfirm = true
                    } label: {
                        Label(L10n.t("断开连接"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } footer: {
                    Text(L10n.t("断开后需要重新扫码或输入访问密码。"))
                }

                Section("DSH Pocket") {
                    HStack {
                        Text(L10n.t("版本"))
                        Spacer()
                        Text(versionText).foregroundStyle(.secondary)
                    }
                }
            }
            .alert(L10n.t("断开与电脑的连接？"), isPresented: $showingDisconnectConfirm) {
                Button(L10n.t("断开连接"), role: .destructive) {
                    model.disconnect()
                    dismiss()
                }
                Button(L10n.t("取消"), role: .cancel) {}
            }
            .onAppear {
                // 探测已由 RootView 按前后台常驻，这里只补一次立即探测，
                // 让用户打开设置页就能看到最新结果，而不是等下一个周期。
                Task {
                    await model.probeRunner.probeRound(addresses: model.savedEndpoints.map(\.address))
                    syncProbeSnapshot()
                }
            }

            .navigationTitle(L10n.t("设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("完成")) { dismiss() }
                }
            }
            .sheet(item: $reorderContext) { context in
                WorkspaceReorderSheet(
                    workspaces: context.workspaces,
                    isDemo: model.isDemoMode,
                    failureReason: context.failure,
                    onRetry: { openReorder() },
                    onMove: { fromId, beforeId in
                        Task { await model.moveWorkspace(fromId, before: beforeId) }
                    },
                    onClose: { reorderContext = nil }
                )
            }
        }
        .id(languageRevision)
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageChanged)) { _ in
            languageRevision &+= 1
        }
    }

}

extension AppSettingsSheet {
    /// 打开排序面板。
    ///
    /// **优先用已有缓存**（新建会话/连接后预加载时拉到的），不重新拉：
    /// 这条 WebSocket 请求在设置页的上下文里不稳定，而缓存里的数据是可靠的。
    /// 只有缓存为空时才尝试加载，失败就给提示和重试按钮。
    fileprivate func openReorder() {
        Task {
            if model.workspaces.isEmpty {
                _ = await model.loadWorkspaces()
            }
            let ordered = WorkspaceParsing.orderedForPicker(model.workspaces, defaultId: nil)
            await MainActor.run {
                reorderContext = ReorderContext(workspaces: ordered,
                                                failure: model.lastWorkspaceLoadError)
            }
        }
    }
}

extension AppSettingsSheet {
    /// 把连接地址翻译成人能一眼认出的方式。
    ///
    /// 判据来自 `DSHEndpointPolicy.kind(of:)` 的同一套 host 规则，但这里要更细：
    /// 用户看到「公网」不知道是 Tailscale 还是 Cloudflare，而这两者的排查方向完全不同。
    var connectionKindLabel: String {
        guard let url = URL(string: model.connection.serverAddress),
              let host = url.host?.lowercased() else {
            return L10n.t("未知")
        }
        if host.hasSuffix(".ts.net") { return "Tailscale" }
        if host.hasSuffix(".trycloudflare.com") { return "Cloudflare" }
        if host == "localhost" || host.hasSuffix(".local") { return L10n.t("局域网") }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            let a = parts[0], b = parts[1]
            if a == 127 || a == 10 || (a == 192 && b == 168) || (a == 172 && (16...31).contains(b)) {
                return L10n.t("局域网")
            }
            return L10n.t("公网直连")
        }
        if url.scheme == "https" { return L10n.t("公网") }
        return L10n.t("自定义")
    }

    /// 状态圆点：绿=HTTP 已连，橙=过渡中，红=断开，灰=未连。
    ///
    /// 优先看 `isConnected`：点「切换」后 HTTP 立刻通，但实时流要等进入会话才起，
    /// 只盯 liveConnection 会让已连上的连接显示成灰点。
    var connectionStatusColor: Color {
        if model.connection.isConnected { return .green }
        switch model.liveConnection {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .disconnected: return .red
        case .idle: return .secondary
        case .demo: return .blue
        }
    }

    /// 当前地址的稳定性：用探测历史，**按地址分开统计**。
    ///
    /// 样本不足时不写「采集中」这种没信息量的词，而是给出进度（2/3）——
    /// 用户能看出「快好了」，而不是「是不是卡住了」。
    var stability: (label: String, color: Color) {
        let address = model.connection.serverAddress
        let s = model.probeRunner.stability.stability(for: address)
        switch s.grade {
        case .unknown:
            let need = 3
            if s.samples == 0 { return (L10n.t("等待首次探测"), Color.secondary) }
            return (L10n.tf("采样中 %d/%d", s.samples, need), Color.secondary)
        case .stable: return (L10n.t("稳定"), Color.green)
        case .occasional: return (L10n.t("偶尔抖动"), Color.yellow)
        case .unstable: return (L10n.t("较不稳定"), Color.orange)
        case .poor: return (L10n.t("频繁断连"), Color.red)
        }
    }

    /// 把探测器的结果同步到 model（供 UI 刷新）。
    func syncProbeSnapshot() {
        model.probeResults = model.probeRunner.results
    }

    /// 切换列表右侧的健康标记：可达显示 RTT，不可达明确写出原因。
    @ViewBuilder
    func healthBadge(for address: String) -> some View {
        switch model.probeResults[address] {
        case .none:
            Text(L10n.t("检测中"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .unreachable:
            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 3) {
                    Image(systemName: "xmark.circle.fill")
                    Text(L10n.t("不可达"))
                }
                .font(.caption2)
                .foregroundStyle(.red)
                // 把错误码也显示出来：-1001 超时 / -1004 连不上 / -1022 ATS，
                // 三者修法完全不同，只显示「不可达」判断不了。
                if let err = model.probeRunner.lastErrors[address] {
                    Text(err)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        case .reachable(let rtt):
            HStack(spacing: 3) {
                Image(systemName: "circle.fill").font(.system(size: 5))
                Text(rtt.map { "\($0) ms" } ?? L10n.t("可达"))
            }
            .font(.caption2)
            .foregroundStyle(.green)
        }
    }
}

/// 最近若干次探测时延的迷你曲线。
///
/// 三条优化（2026-11-21 用户反馈「像折线碎片」）：
/// 1. **均匀铺满宽度**：不受失败点占位影响，2 个点也画满整条，不再缩在右边；
/// 2. **单点画圆**：刚启动只有一次探测时给一个点，而不是什么都不画；
/// 3. **失败点标红**：曲线断开处补一个红点，一眼看出「这里断了」。
struct Sparkline: View {
    let series: LatencySeries?
    var height: CGFloat = 14

    var body: some View {
        Canvas { context, size in
            guard let series, let range = series.plotRange else { return }
            let values = series.samples
            guard !values.isEmpty else { return }

            let span = range.upperBound - range.lowerBound
            let stepX = values.count > 1 ? size.width / CGFloat(values.count - 1) : 0
            let midY = size.height / 2

            // 按失败点切段：成功点连线，失败点断开
            var segments: [[CGPoint]] = []
            var current: [CGPoint] = []
            var failures: [CGPoint] = []
            for (index, value) in values.enumerated() {
                let x = values.count > 1 ? CGFloat(index) * stepX : size.width / 2
                guard let value else {
                    if !current.isEmpty { segments.append(current); current = [] }
                    failures.append(CGPoint(x: x, y: size.height - 2))
                    continue
                }
                let normalized = (Double(value) - range.lowerBound) / span
                let y = size.height - CGFloat(normalized) * (size.height - 4) - 2
                current.append(CGPoint(x: x, y: y))
            }
            if !current.isEmpty { segments.append(current) }

            let tint = Color.green
            for segment in segments {
                if segment.count == 1, let only = segment.first {
                    // 只有一个成功点时画实心圆，否则看不出变化
                    let r: CGFloat = 1.8
                    let rect = CGRect(x: only.x - r, y: only.y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(tint))
                } else {
                    var path = Path()
                    path.move(to: segment[0])
                    for point in segment.dropFirst() { path.addLine(to: point) }
                    context.stroke(path, with: .color(tint),
                                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }

            for point in failures {
                let r: CGFloat = 1.4
                let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.red))
            }
        }
        .frame(height: height)
        .accessibilityLabel(L10n.t("最近时延曲线"))
    }
}
