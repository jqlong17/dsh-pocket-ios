// 诊断

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

/// 诊断出口：运行时日志、采样、会话进出记录、可复制的诊断报告。
///
/// 从 ConnectionModel+Connect 拆出来（纯文件搬迁）：诊断与连接流程没有交集，
/// 混在一起会让「连接」这个最需要专注的流程里躺着 200 行日志代码。
extension ConnectionModel {

   func recordDiagnostic(_ message: String) {
        diagnostics.record(message)
    }


    /// 复制诊断信息：结构化英文报告（格式见 DSHKit 的 DiagnosticsReport）。
    ///
    /// 为什么全英文而不是跟随语言：这份文本的读者是排查问题的人，跨语言时英文是默认约定；
    /// App 内其他文案继续本地化。
    @MainActor
    func diagnosticReport() -> String {
        captureDiagnosticSample()
        let s = conversationSizeSnapshot()
        let hasSession = !currentConversationTitle.isEmpty
        let counts = diagnosticSendCounts()
        let breakdown = Diagnostics.memoryBreakdown()
        let images = ImageMemory.shared.stats()
        let kept = diagnostics.providers?.retainedStats() ?? (0, 0, 0, 0)

        var sections: [DiagnosticsReport.Section] = []
        sections.append(.init("Connection", [
            ("State", connection.isConnected ? "connected" : "disconnected"),
            // 脱敏函数同时服务于 UI 弹窗，解析失败时返回中文；报告是英文的，
            // 所以这里只在「能解析出 host」时用它，否则用占位符。
            ("Server", URL(string: connection.serverAddress)?.host?.isEmpty == false
                ? DSHURL.redactedAddress(connection.serverAddress)
                : DiagnosticsReport.missing),
            ("Live", liveConnection.reportLabel),
            ("Demo mode", isDemoMode ? "yes" : "no")
        ]))
        sections.append(.init("Session", hasSession ? [
            ("Title", s.title),
            ("Messages", "\(s.messages)  (user \(s.userMessages) / assistant \(s.assistantMessages) / pending \(s.pendingMessages))"),
            ("Steps", "\(s.steps)  (unfinished \(s.unfinishedSteps) / error \(s.errorSteps) / groups \(s.stepGroups))"),
            ("Timeline", "\(s.timelineRows) rows · failed turns \(s.failures)"),
            ("Has more", s.hasMore ? "yes" : "no"),
            ("Load", s.loadMs.map { "\($0) ms via \(s.loadSource ?? "unknown")" } ?? DiagnosticsReport.missing)
        ] : [("Title", DiagnosticsReport.missing)]))
        sections.append(.init("Storage", [
            ("Message text", DiagnosticsReport.bytes(s.messageBytes)),
            ("Step results", DiagnosticsReport.bytes(s.stepBytes)),
            ("Images", "\(s.images) refs · cache \(s.cachedImages) / \(DiagnosticsReport.bytes(s.cachedImageBytes))"),
            ("Live views", "\(s.liveViews)")
        ]))
        sections.append(.init("Memory", [
            ("Footprint", "\(breakdown.footprintMB) MB"),
            ("Compressed", "\(breakdown.compressedMB) MB"),
            ("Images held", "\(images.count) / \(DiagnosticsReport.bytes(images.bytes))"),
            ("Retained", "\(kept.0) sessions · \(kept.1) msgs · text \(DiagnosticsReport.bytes(kept.2))")
        ]))
        sections.append(.init("Outbox", [
            ("Counts", "pending \(counts.pending) · queued \(counts.queued) · failed \(counts.failed)"),
            ("Flushing", outbox.flushInFlight ? "yes" : "no")
        ]))

        // 事件行固定英文：样本里的网络文案已经是英文标识（见 diagnosticNetworkLabel）。
        let events = diagnostics.samples.map { sample in
            DiagnosticsReport.eventLine(
                at: sample.at,
                text: "mem \(sample.memoryMB)MB · pending \(sample.pending) · queued \(sample.queued) · failed \(sample.failed) · net \(sample.network)"
            )
        }
        let notes = [
            "Footprint is phys_footprint for the whole process, not the conversation's text size.",
            "Step count is not row count — the UI draws one row per step group.",
            "Live views should return to 0 after leaving a conversation."
        ]
        return DiagnosticsReport.render(.init(
            header: .init(generated: Date(),
                          appVersion: AppInfo.version,
                          build: AppInfo.build,
                          device: AppInfo.deviceModel,
                          system: AppInfo.systemVersion,
                          locale: AppInfo.localeIdentifier),
            sections: sections,
            events: events,
            notes: notes
        ))
    }


   func startDiagnosticSampler() {
        diagnostics.startSampler { [weak self] in
            self?.captureDiagnosticSample()
        }
    }


   func diagnosticMemoryLine() -> String { diagnostics.memoryLine() }


   func conversationSizeSnapshot() -> ConversationSizeSnapshot {
        let user = messages.filter(\.isUser).count
        return ConversationSizeSnapshot(
            title: currentConversationTitle,
            messages: messages.count,
            userMessages: user,
            assistantMessages: messages.count - user,
            pendingMessages: messages.filter(\.isPending).count,
            steps: steps.count,
            unfinishedSteps: steps.filter { !$0.finished }.count,
            errorSteps: steps.filter(\.isError).count,
            stepGroups: stepGroups.count,
            failures: turnFailures.count,
            timelineRows: messages.count + stepGroups.count + turnFailures.count,
            messageBytes: messages.reduce(0) { $0 + $1.text.utf8.count },
            stepBytes: steps.reduce(0) { $0 + $1.resultText.utf8.count + $1.detail.utf8.count },
            images: messages.reduce(0) { $0 + $1.images.count + $1.localImages.count }
                + steps.reduce(0) { $0 + $1.images.count },
            cachedImages: ImageMemory.shared.stats().count,
            cachedImageBytes: ImageMemory.shared.stats().bytes,
            liveViews: ConversationViewLifetime.liveCount,
            hasMore: hasMoreOlder,
            loadMs: activeConversation?.lastLoadMs,
            loadSource: activeConversation?.lastLoadSource,
            memoryMB: String(format: "%.1f", Diagnostics.memoryFootprintMB())
        )
    }


    @MainActor
    func installDiagnosticsProviders() {
        guard diagnostics.providers == nil else { return }
        diagnostics.providers = Diagnostics.Providers(
            memoryBreakdown: { Diagnostics.memoryBreakdown() },
            retainedStats: { @MainActor [weak self] in
                self?.retainedConversationStats() ?? (0, 0, 0, 0)
            },
            sendCounts: { @MainActor [weak self] in
                self?.diagnosticSendCounts() ?? (0, 0, 0)
            },
            networkLabel: { @MainActor [weak self] in
                self?.diagnosticNetworkLabel() ?? "未知"
            },
            conversationStats: { @MainActor [weak self] in
                self?.conversationSizeSnapshot() ?? ConversationSizeSnapshot(
                    title: "", messages: 0, userMessages: 0, assistantMessages: 0,
                    pendingMessages: 0, steps: 0, unfinishedSteps: 0, errorSteps: 0,
                    stepGroups: 0, failures: 0, timelineRows: 0, messageBytes: 0,
                    stepBytes: 0, images: 0, cachedImages: 0, cachedImageBytes: 0,
                    liveViews: 0, hasMore: false, loadMs: nil, loadSource: nil, memoryMB: "—")
            },
            logPath: { [weak self] in self?.sessionLogPath },
            sessionAddress: { [weak self] in self?.sessionAddress ?? "" }
        )
    }


   func conversationDiagnosticsBlock() -> String { diagnostics.indexBlock() }


   func beginDiagnosticVisit(reusedMessages: Int) {
        diagnostics.beginVisit(reusedMessages: reusedMessages,
                               memoryMB: Int(Diagnostics.memoryFootprintMB().rounded()))
        captureDiagnosticSample()
    }


   func finishDiagnosticVisit(leaveMs: Int) {
        guard let visitIndex = diagnostics.finishVisit(leaveMs: leaveMs,
                                                       memoryMB: Int(Diagnostics.memoryFootprintMB().rounded())) else { return }
        captureDiagnosticSample()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard self.visibleSessionId == nil else { return }
            self.diagnostics.setViewsAfterLeave(visitIndex: visitIndex,
                                                views: ConversationViewLifetime.liveCount)
        }
    }


   func stopDiagnosticSampler() {
        diagnostics.stopSampler()
    }


   func captureDiagnosticSample(enterMs: Int? = nil) {
        diagnostics.capture(enterMs: enterMs)
    }


   func noteNetworkEdgeForDiagnostics() {
        switch liveConnection {
        case .disconnected, .reconnecting:
            if networkDownSince == nil { networkDownSince = Date() }
        default:
            networkDownSince = nil
        }
    }


   func diagnosticNetworkLabel() -> String {
        // 采样只喂给诊断报告（英文），所以这里直接用英文标识，避免报告里再翻译一次。
        switch liveConnection {
        case .reconnecting, .disconnected:
            let seconds = max(Int(Date().timeIntervalSince(networkDownSince ?? Date())), 0)
            return "\(liveConnection.reportLabel) \(seconds)s"
        default:
            return liveConnection.reportLabel
        }
    }


   func diagnosticSendCounts() -> (pending: Int, queued: Int, failed: Int) {
        var pending = 0
        var queued = 0
        var failed = 0
        for message in messages where message.isPending {
            switch pendingSendState(for: message) {
            case .failed:
                failed += 1
            case .queued:
                queued += 1
            case .sending, .none:
                pending += 1
            case .acked:
                break
            }
        }
        return (pending, queued, failed)
    }


   func noteLoadFinished(source: String, conversation: ConversationState) {
        guard conversation.loadTimingPending, let started = conversation.loadStartedAt else { return }
        conversation.loadTimingPending = false
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        conversation.lastLoadMs = ms
        conversation.lastLoadSource = source
        recordDiagnostic("会话加载 \(ms) ms source=\(source) 消息=\(conversation.messages.count) 过程=\(conversation.steps.count)")
        captureDiagnosticSample(enterMs: ms)
        diagnostics.setEnterMsForOpenVisit(ms)
    }


}
