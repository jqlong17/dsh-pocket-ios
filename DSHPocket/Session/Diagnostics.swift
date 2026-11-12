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
