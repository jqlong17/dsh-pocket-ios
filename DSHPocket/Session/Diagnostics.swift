// Diagnostics

import Foundation
import Observation

/// 诊断数据的所有者：采样、进出记录、运行日志。
///
/// 边界（重要）：本类型**只持有自己的数据，不反向依赖 ConnectionModel**。
/// 需要外部信息（内存、待发数量、网络状态）时由调用方算好传进来，
/// 否则 Diagnostics 就会反过来依赖整个模型，失去可独立测试与替换的意义（见 spec/12）。
@Observable
final class Diagnostics {
    /// 最近的采样行，用于「更多 → 复制诊断信息」。
    private(set) var samples: [DiagnosticSample] = []
    /// 会话进出记录（含复用消息数、进/出耗时、退出后视图残留）。
    private(set) var visits: [DiagnosticVisit] = []
    /// 运行时最近 30 条日志（供反馈时导出）。
    private(set) var history: [String] = []

    private var sampleTask: Task<Void, Never>?

    /// 外部数据来源。诊断需要内存、待发计数、网络状态等模型知识，
    /// 但**不能反向依赖 ConnectionModel**，所以由模型在启动时装配成闭包。
    struct Providers {
        var memoryBreakdown: () -> (footprintMB: Int, compressedMB: Int)
        var retainedStats: () -> (sessions: Int, messages: Int, textBytes: Int, stepBytes: Int)
        var sendCounts: () -> (pending: Int, queued: Int, failed: Int)
        var networkLabel: () -> String
        var conversationStats: () -> ConversationSizeSnapshot
        var logPath: () -> String?
        var sessionAddress: () -> String
    }

    var providers: Providers?

    static let historyLimit = 30
    static let visitLimit = 6

    // MARK: 日志

    func record(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)"
        history.append(line)
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
        NSLog("DSH_DIAG %@", line)
        Self.appendToFile(line)
    }

    /// 设备日志不可靠（过滤/断连），同时落盘到沙盒，可用 devicectl 直接拉取。
    static func appendToFile(_ line: String) {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = directory.appendingPathComponent("diagnostics.log")
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: 采样

    func appendSample(_ sample: DiagnosticSample) {
        samples.append(sample)
        // 只保留最近 24 条：诊断信息是给人看的，不是历史数据库。
        if samples.count > 24 {
            samples.removeFirst(samples.count - 24)
        }
    }

    /// 启动 10 秒采样。采集内容由调用方提供（本类型不持有业务状态）。
    func startSampler(capture: @escaping () -> Void) {
        guard sampleTask == nil else { return }
        sampleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if Task.isCancelled { break }
                await MainActor.run {
                    guard self != nil else { return }
                    capture()
                }
            }
        }
    }

    func stopSampler() {
        sampleTask?.cancel()
        sampleTask = nil
    }

    // MARK: 进出

    func beginVisit(reusedMessages: Int, memoryMB: Int) {
        let nextIndex = (visits.last?.index ?? 0) + 1
        visits.append(DiagnosticVisit(index: nextIndex,
                                      enterMs: nil,
                                      leaveMs: nil,
                                      reusedMessages: reusedMessages,
                                      memoryEnter: memoryMB,
                                      memoryLeave: nil,
                                      viewsAfterLeave: nil))
        if visits.count > Self.visitLimit {
            visits.removeFirst(visits.count - Self.visitLimit)
        }
    }

    /// 结束最近一条未闭合的进出记录，返回它的 index（供稍后补 viewsAfterLeave）。
    @discardableResult
    func finishVisit(leaveMs: Int, memoryMB: Int) -> Int? {
        guard let slot = visits.lastIndex(where: { $0.leaveMs == nil }) else { return nil }
        visits[slot].leaveMs = leaveMs
        visits[slot].memoryLeave = memoryMB
        return visits[slot].index
    }

    /// 首次加载完成后回填这次进入的耗时。
    func setEnterMsForOpenVisit(_ ms: Int) {
        guard let slot = visits.lastIndex(where: { $0.leaveMs == nil }) else { return }
        visits[slot].enterMs = ms
    }

    /// 退出会话 0.7 秒后回填「视图还剩几个」。
    func setViewsAfterLeave(visitIndex: Int, views: Int) {
        guard let slot = visits.lastIndex(where: { $0.index == visitIndex }),
              visits[slot].leaveMs != nil else { return }
        visits[slot].viewsAfterLeave = views
    }

    // MARK: 报告

    /// 生成可复制的诊断文本。标题与内存行由调用方提供，避免反向依赖。
    func report(title: String, memoryLine: String) -> String {
        let visitLines = visits.map(\.line)
        let sampleLines = samples.map(\.line)
        return """
        \(title)
        进出
        \(visitLines.isEmpty ? "还没有进出记录" : visitLines.joined(separator: "\n"))
        此刻
        \(memoryLine)
        采样
        \(sampleLines.isEmpty ? "还没有采样" : sampleLines.joined(separator: "\n"))
        """
    }
}

// MARK: - 采集与报告（数据源由 providers 注入）

extension Diagnostics {
    /// 采样一行：内存、待确认/断网/失败条数、网络状态。
    func capture(enterMs: Int? = nil) {
        guard let providers else { return }
        let counts = providers.sendCounts()
        let breakdown = providers.memoryBreakdown()
        let sample = DiagnosticSample(at: Date(),
                                      memoryMB: breakdown.footprintMB,
                                      pending: counts.pending,
                                      queued: counts.queued,
                                      failed: counts.failed,
                                      network: providers.networkLabel(),
                                      enterMs: enterMs)
        if let last = samples.last,
           enterMs == nil,
           last.at.timeIntervalSinceNow > -2,
           last.pending == sample.pending,
           last.queued == sample.queued,
           last.failed == sample.failed,
           last.network == sample.network {
            return
        }
        appendSample(sample)
    }

    /// 「此刻」那一行：内存、图片缓存、文本体积、会话页数。
    func memoryLine() -> String {
        guard let providers else { return "诊断数据源未装配" }
        let detail = providers.memoryBreakdown()
        let kept = providers.retainedStats()
        let images = ImageMemory.shared.stats()
        return "内存 \(detail.footprintMB)MB  压缩 \(detail.compressedMB)MB  图 \(images.count)张/\(Self.formatBytes(images.bytes))  文字 \(Self.formatBytes(kept.textBytes))  过程正文 \(Self.formatBytes(kept.stepBytes))  页 \(ConversationViewLifetime.liveCount)  留着会话 \(kept.sessions)（消息 \(kept.messages)）"
    }

    /// 复制诊断信息里的「状态索引」段：解释每一项含义，给排查的人看。
    func indexBlock() -> String {
        guard let providers else { return "诊断数据源未装配" }
        let s = providers.conversationStats()
        let load = s.loadMs.map { "\($0) ms，来源 \(s.loadSource ?? "未知")" } ?? "这次打开还没记到加载完成"
        let log = providers.logPath() ?? "没有 cwd，推不出电脑上的会话日志路径"
        let address = providers.sessionAddress()
        return """
        --- 状态索引 ---
        这份文本是给排查用的，不是给用户看的菜单。上面是此刻的汇总，下面是最近事件。要更早的记录，按「去哪看」取文件。

        会话: \(s.title)
        地址: \(address.isEmpty ? "未打开会话" : address)
        电脑日志: \(log)
        手机日志: App 沙盒 Documents/diagnostics.log。用 devicectl device copy from --domain-type appDataContainer 拉取。控制台过滤 DSH_DIAG。
        会话日志格式: ~/.dsh/sessions/--<cwd 里的 / 换成 ->--/<sessionId>/session.v4.jsonl.zstd

        消息 \(s.messages)（用户 \(s.userMessages) / 助手 \(s.assistantMessages) / 待发 \(s.pendingMessages)）
        含义: 手机上这次加载进来的消息条数，不是电脑上的全部历史。待发是还没被服务端确认的本地气泡。
        还有更早: \(s.hasMore ? "是，向上翻还会再拉" : "否，当前窗口已经到最早")

        过程 \(s.steps)（未完成 \(s.unfinishedSteps) / 出错 \(s.errorSteps) / 界面上折叠成 \(s.stepGroups) 组）
        含义: 工具步骤。未完成=还在跑；出错=工具结果是错误。组数才是屏幕上画出来的过程行，不要用步骤数当行数。
        失败轮次: \(s.failures)。时间线上要布局的行: \(s.timelineRows)（消息 + 过程组 + 失败提示）。

        文本体积: 消息 \(Self.formatBytes(s.messageBytes))，过程结果 \(Self.formatBytes(s.stepBytes))
        含义: 只算已留在内存里的文字。过程正文默认不保留，展开后才会变大。这不是 内存 那一项。

        图片 \(s.images) 张，缩略图缓存 \(s.cachedImages) 张 / \(Self.formatBytes(s.cachedImageBytes))
        含义: 图片引用数，加上 ImageMemory 里实际解码的缩略图。缓存有上限（48 张 / 32 MB）。全尺寸图不应该留在这里。

        会话页还活着: \(s.liveViews)
        含义: ConversationView 实例数。离开会话后应回到 0。大于 1 说明旧页面没释放，反复进出时内存会叠。

        上次加载: \(load)
        含义: 从开始打开到首屏内容到齐的耗时。follow=实时流快照，history=HTTP 拉的历史。慢的时候先看过程组数和图片数，不要先怪网络。

        App 内存: \(s.memoryMB) MB
        含义: phys_footprint，整个进程现在有多重，不是这段对话的文本大小。iOS 杀后台看的就是这个数。文字通常只有几十 KB；涨到几百 MB 时先看图片缓存和会话页是否还活着。

        --- 最近事件（最多 30 条，更早的在手机日志文件） ---
        """
    }

    // MARK: 纯工具

    /// Jetsam 看的物理占用，比 resident size 更接近「这个 App 现在有多重」。
    static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1_048_576
    }

    static func memoryBreakdown() -> (footprintMB: Int, compressedMB: Int) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (-1, -1) }
        return (Int((Double(info.phys_footprint) / 1_048_576).rounded()),
                Int((Double(info.compressed) / 1_048_576).rounded()))
    }

    static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
