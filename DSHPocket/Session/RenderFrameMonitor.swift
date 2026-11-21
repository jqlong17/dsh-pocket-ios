import Foundation
import QuartzCore
import Observation

/// 滚动帧率监控：用 `CADisplayLink` 统计「间隔超过 2 帧时长」的比例。
///
/// 为什么需要它：`renderMs` 只测数据重排（实测 0.1ms，完全不是瓶颈），
/// 而「滚动手感发涩」属于**合成/绘制**问题——只有帧率能反映。
@Observable
@MainActor
final class RenderFrameMonitor {
    /// 最近窗口内超时帧占比（0...1）。
    private(set) var slowFrameRatio: Double = 0
    /// 最近窗口的平均帧间隔（毫秒）。60Hz 理想值 16.7ms。
    private(set) var averageIntervalMs: Double = 0
    /// 累计采样帧数。
    private(set) var sampledFrames: Int = 0

    /// 显式 nonisolated：ConnectionModel 在非隔离上下文里构造它。
    nonisolated init() {}

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var intervals: [Double] = []
    private let windowSize = 120

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: FrameProxy { [weak self] in self?.tick() },
                                 selector: #selector(FrameProxy.tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastTimestamp = 0
        intervals.removeAll()
    }

    private func tick() {
        let now = CACurrentMediaTime()
        defer { lastTimestamp = now }
        guard lastTimestamp > 0 else { return }
        let delta = (now - lastTimestamp) * 1000
        // 过滤掉「App 切后台再回来」造成的巨大间隔（不是掉帧）
        guard delta < 200 else { return }
        intervals.append(delta)
        if intervals.count > windowSize { intervals.removeFirst(intervals.count - windowSize) }
        guard intervals.count >= 10 else { return }
        let threshold = 2 * (1000.0 / 60.0)   // 超过 2 帧时长算慢帧
        let slow = intervals.filter { $0 > threshold }.count
        slowFrameRatio = Double(slow) / Double(intervals.count)
        averageIntervalMs = intervals.reduce(0, +) / Double(intervals.count)
        sampledFrames += 1
    }
}

/// CADisplayLink 需要 Objective-C target，用一个轻量代理转发到闭包。
private final class FrameProxy: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func tick() { handler() }
}
