import BackgroundTasks
import Foundation
import UIKit

/// 后台刷新：iOS 在合适时机唤醒 App 几十秒，让它在「锁屏/挂起」状态下也能发现 AI 跑完并发本地通知。
///
/// 为什么需要它：本地通知只能由「正在运行的 App」发出。用户锁屏后 iOS 会挂起 App，
/// 轮询停止 → 检测不到「运行中 → 已结束」→ 连通知都不会发（这就是之前「锁屏收不到」的真因）。
///
/// 为什么不用 APNs：APNs 凭证属于开发者，不属于用户。每个用户有自己的 Mac 和 DSH，
/// 但没有人有自己的 APNs Key；把 Key 打包进客户端是严重违规。详见
/// `~/projects/skill/代码编写规范/ios踩坑记录.md` 第 29 条。
///
/// 代价：**唤醒时机由 iOS 决定**，实测延迟从几十秒到几十分钟不等；低电量时更保守。
@MainActor
enum BackgroundRefresh {
    /// 必须与 `Info.plist` 的 `BGTaskSchedulerPermittedIdentifiers` 一致。
    static let taskIdentifier = "com.ruska.dsh-pocket-ios.refresh"

    /// 最短重排间隔。
    ///
    /// 15 分钟太长：用户锁屏几分钟就想知道 AI 跑完没有，实测 6 分钟的锁屏完全等不到唤醒。
    /// 改成 2 分钟，让「短时锁屏」也能被覆盖。iOS 仍会按自己的判断合并/推迟，
    /// 这里只是「最早可以跑」的时间，不是保证。
    private static let earliestInterval: TimeInterval = 2 * 60

    /// 在 `didFinishLaunching` 里调用：注册处理器并排一次刷新。
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            MainActor.assumeIsolated {
                handle(refreshTask)
            }
        }
        schedule()
    }

    /// 排下一次刷新。每次处理完都要重新排，否则只会跑一次。
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliestInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // 模拟器/未声明能力时会失败，不影响前台使用，只记诊断。
            NSLog("DSH_POCKET bg refresh schedule failed: %@", error.localizedDescription)
        }
    }

    /// 处理一次唤醒：用已保存的连接拉一次会话，跑完成检测，然后立刻重排。
    private static func handle(_ task: BGAppRefreshTask) {
        // 先排下一次：即使本次超时/失败，也不会把后续刷新断掉。
        schedule()

        let work = Task { @MainActor in
            // 后台只需要「拉列表 + 判完成」，用一个临时 model 走既有恢复路径即可，
            // 不依赖前台的 ConnectionModel 实例（它在后台可能已被释放）。
            let model = ConnectionModel()
            await model.restoreConnection()
            guard model.connection.isConnected else {
                task.setTaskCompleted(success: false)
                return
            }
            // restoreConnection 已经拉过一次 fetchSessions，这里直接判完成。
            await model.detectSessionCompletions()
            task.setTaskCompleted(success: true)
        }

        // 系统给的执行时间有限（约 30 秒），超时就主动收尾，避免被强杀。
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
