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


   func diagnosticReport() -> String {
        captureDiagnosticSample()
        let title = currentConversationTitle.isEmpty ? "未打开会话" : currentConversationTitle
        return diagnostics.report(title: title, memoryLine: diagnosticMemoryLine())
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
        switch liveConnection {
        case .connected:
            return "通"
        case .demo:
            return "演示"
        case .connecting:
            return "连接中"
        case .reconnecting:
            let seconds = Int(Date().timeIntervalSince(networkDownSince ?? Date()))
            return "重连 \(max(seconds, 0)) 秒"
        case .disconnected:
            let seconds = Int(Date().timeIntervalSince(networkDownSince ?? Date()))
            return "断 \(max(seconds, 0)) 秒"
        case .idle:
            return "未连接"
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
