// NetworkWatcher

import Foundation
import Network

/// 网络可达性监听：从「不可用」变为「可用」时通知一次。
///
/// 为什么需要它：补发原先只靠两个被动触发点——
/// 1. 列表刷新成功（10 秒轮询一次）；
/// 2. 实时流收到帧（要先重连上 WS）。
/// 用户断网发消息后恢复网络，若 WS 还没重连、轮询又没到点，消息就一直停在
/// 「现在断网，等联网时将一并发送」——看起来像卡住了。有了路径监听，恢复即刻补发。
///
/// 只关心「变为可用」这一个边沿，丢掉 satisfied 的重复回调（系统会多次触发）。
final class NetworkWatcher {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dsh-pocket.network-watcher")
    private var lastSatisfied: Bool?

    /// 网络从不可用变为可用时回调（主线程）。
    var onBecomeReachable: (@MainActor () -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let satisfied = path.status == .satisfied
            let previous = self.lastSatisfied
            self.lastSatisfied = satisfied
            // 只在「第一次知道可用」或「从不可用变可用」时通知。
            guard satisfied, previous != true else { return }
            Task { @MainActor [weak self] in
                self?.onBecomeReachable?()
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
