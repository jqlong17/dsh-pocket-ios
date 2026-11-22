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

        // ── Pagination 段：暂时注释 ──────────────────────────────────────────
        //
        // 为什么注释：产品已明确「只保留最近 30 条、不提供往上翻更早历史」（方案 B），
        // 所以这几项现在恒为固定值（Has more=no / Attempts=0），留在报告里是噪音。
        //
        // 但**统计字段仍在正常维护**（ConversationState.olderLoadAttempts / Successes /
        // LastAdded / LastAt / LastResult，以及 loadOlderMessages 和 .messages 分支里的写入点），
        // 日后如果恢复「上滑加载历史」，把下面这段注释解开就能直接用，不用重新接线。
        //
        // 恢复步骤：
        //   1. 解开这段注释
        //   2. ConnectionModel+Live 的 snapshot 分支去掉 `hasMoreOlder = false`（改回 hasMore）
        //   3. ConnectionModel+Live 的 .messages 分支恢复「按方向裁剪」
        //
        // if let conversation = activeConversation {
        //     var rows: [(String, String)] = [
        //         ("Has more", hasMoreOlder ? "yes" : "no"),
        //         ("Loading older", isLoadingOlder ? "yes" : "no"),
        //         ("Attempts", "\(conversation.olderLoadAttempts) (success \(conversation.olderLoadSuccesses))")
        //     ]
        //     if let result = conversation.olderLoadLastResult {
        //         let ago = conversation.olderLoadLastAt.map { "\(Int(Date().timeIntervalSince($0)))s ago" } ?? "—"
        //         rows.append(("Last load", "\(result) · \(ago)"))
        //     }
        //     rows.append(("Messages now", "\(conversation.messages.count)"))
        //     sections.append(.init("Pagination", rows))
        // }

        // 实时帧信号：卡顿时用来区分「没收到帧」和「收到帧但渲染慢」。
        // 前者是网络/服务端问题，后者是客户端渲染问题——过去只能靠猜。
        if let conversation = activeConversation {
            let frameTimes = conversation.recentFrameTimes
            var rows: [(String, String)] = [
                ("Frames", "\(frameTimes.count) / 120 (ring buffer)")
            ]
            if let newest = frameTimes.last, let oldest = frameTimes.first, frameTimes.count >= 2 {
                let windowSeconds = newest.timeIntervalSince(oldest)
                let rate = windowSeconds > 0 ? Double(frameTimes.count - 1) / windowSeconds : 0
                let gaps = zip(frameTimes.dropFirst(), frameTimes).map { $0.timeIntervalSince($1) }
                let avgGap = gaps.reduce(0, +) / Double(max(gaps.count, 1))
                let maxGap = gaps.max() ?? 0
                rows.append(("Rate", String(format: "%.2f /s over %.1fs", rate, windowSeconds)))
                rows.append(("Gap avg", "\(Int(avgGap * 1000)) ms"))
                rows.append(("Gap max", "\(Int(maxGap * 1000)) ms"))
            }
            rows.append(("Since frame", "\(Int(Date().timeIntervalSince(conversation.lastLiveFrameAt) * 1000)) ms"))
            sections.append(.init("Live Signal", rows))
        }

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
        // 把探测器结果镜像到模型上：`probeRunner` 是 @ObservationIgnored 的嵌套对象，
        // 它的内部改动不会让设置页刷新（实测：遥测有 26ms，界面一直写「检测中」）。
        MainActor.assumeIsolated {
            probeResults = probeRunner.results
            probeLatency = probeRunner.latencyHistory
        }
        // 采样器本身就是 10 秒一次，和 Mac 侧 dsh-net-record 同频，
        // 顺手把「只有手机知道」的状态报上去，两边时间轴才能对齐。
        reportTelemetry()
    }

    /// 把当前连接/发件箱状态报给 Mac（落成 app-telemetry-*.jsonl）。
    ///
    /// 只报状态与计数：**不报消息正文、不报 token、不报地址以外的敏感内容**。
    /// 失败静默（见 TelemetryReporter），不影响任何用户可见行为。
    func reportTelemetry() {
        let base = connection.serverAddress.isEmpty ? nil : URL(string: connection.serverAddress)
        let entries = outboxEntries
        let payload: [String: Any] = [
            "phase": "sample",
            "liveState": diagnosticNetworkLabel(),
            "connected": connection.isConnected,
            "pending": entries.count,
            "queued": entries.filter(\.heldOffline).count,
            "failed": entries.filter(\.sendFailed).count,
            "memoryMB": Diagnostics.memoryFootprintMB(),
            "hasVisibleSession": visibleSessionId != nil,
            "probes": probeSnapshot(),
            "probeNetwork": probeNetworkLabel(),
            "testMode": probeTestMode(),
            "visibleSessionId": visibleSessionId ?? "",
            "appActive": isAppActive,
            "alertsEnabled": completionAlertsEnabled,
            "renderMs": (lastRenderMs * 10).rounded() / 10,
            "renderMsgCount": lastRenderMessageCount,
            // 合并诊断：raw = 内存里的条数，merged = 按 turn 合并后的条数。
            // 两个数相等只说明这批消息没有同 turn 的，不代表合并坏了。
            "rawMsgCount": lastRawMessageCount,
            "mergedMsgCount": lastMergedMessageCount,
            // 上滑历史：开关是否为真、请求过几次、上次结果。
            "hasMoreOlder": hasMoreOlder,
            "olderLoadAttempts": activeConversation?.olderLoadAttempts ?? 0,
            "olderLoadResult": activeConversation?.olderLoadLastResult ?? "",
            "msgCount": messages.count,
            "renderStepGroups": lastRenderStepGroupCount,
            "renderMode": renderModeLabel,
            "slowFrameRatio": frameStats().ratio,
            "frameIntervalMs": frameStats().intervalMs,
        ]
        TelemetryReporter.report(payload, to: base)
    }


   /// 探测结果快照，供遥测上报。
   ///
   /// 形状：[{"address": ..., "ok": true/false, "rttMs": 12, "error": ...}]
   /// 只报地址和结果，不带凭证。


   /// 帧率统计快照（MainActor 隔离，避免跨隔离域读 @Observable 属性）。
   func frameStats() -> (ratio: Double, intervalMs: Double) {
        MainActor.assumeIsolated {
            ((frameMonitor.slowFrameRatio * 1000).rounded() / 1000,
             (frameMonitor.averageIntervalMs * 10).rounded() / 10)
        }
   }


   /// 测试模式是否开启。遥测里带上它，分析时能区分「采样稀疏」和「真没数据」。
   func probeTestMode() -> Bool {
        MainActor.assumeIsolated { probeRunner.testMode }
   }

   /// 探测时认为的网络类型。诊断用：能直接看出「为什么走的是 TCP 而不是 HTTP」。
   func probeNetworkLabel() -> String {
        MainActor.assumeIsolated {
            switch probeRunner.networkClass {
            case .wifi: return "wifi"
            case .cellular: return "cellular"
            case .other: return "other"
            }
        }
   }

   func probeSnapshot() -> [[String: Any]] {
        // `ConnectionModel` 没标 @MainActor，但这些方法实际都在主线程调用
        // （采样器走 `MainActor.run`）。`assumeIsolated` 把这个事实告诉编译器，
        // 比给整条调用链加 @MainActor 干净（那样会连锁报错）。
        MainActor.assumeIsolated {
        let runner = probeRunner
        return savedEndpoints.map { endpoint in
            var row: [String: Any] = [
                "address": endpoint.address,
                "isCurrent": endpoint.address == connection.serverAddress,
            ]
            switch runner.results[endpoint.address] {
            case .reachable(let rtt):
                row["ok"] = true
                if let rtt { row["rttMs"] = rtt }
            case .unreachable:
                row["ok"] = false
            case .none:
                row["ok"] = false
                row["pending"] = true
            }
            if let err = runner.lastErrors[endpoint.address] { row["error"] = err }
            return row
        }
        }
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
