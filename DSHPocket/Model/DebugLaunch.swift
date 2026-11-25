// DebugLaunch

import SwiftUI
import Security
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

enum DebugLaunch {
    static var server: String? { environment["DSH_SERVER"] ?? value(for: "--dsh-server") }
    static var pin: String? { environment["DSH_PIN"] ?? value(for: "--dsh-pin") }
    static var sessionId: String? { environment["DSH_OPEN"] ?? value(for: "--dsh-open") }
    static var sendText: String? { environment["DSH_SEND"] ?? value(for: "--dsh-send") }
    static var loadOlderCount: Int {
        guard let raw = environment["DSH_LOAD_OLDER"] else { return 0 }
        return Int(raw) ?? (raw == "1" ? 1 : 0)
    }
    static var showConnect: Bool { environment["DSH_CONNECT"] == "1" }
    static var attachPath: String? { environment["DSH_ATTACH"] ?? value(for: "--dsh-attach") }
    static var demoMode: Bool { environment["DSH_DEMO"] == "1" }
    /// 调试/UI 测试：演示会话里带一条发送失败的消息，用来验证「重发 / 删除」。
    static var demoFailedMessage: Bool { environment["DSH_DEMO_FAILED"] == "1" }
    /// 调试/UI 测试：演示模式里预置两台主机（一台 3 条地址、一台 1 条），
    /// 用来验证「删一条地址不能连累别的地址」「删一台不能连累别的机器」。
    static var demoHosts: Bool { environment["DSH_DEMO_HOSTS"] == "1" }
    /// 截图/演示用：隐藏「演示模式」状态行，让界面更接近真实使用。
    static var hideDemoBanner: Bool { environment["DSH_HIDE_DEMO_BANNER"] == "1" }
    /// 截图用：打开会话后自动展开所有「过程」。
    static var expandSteps: Bool { environment["DSH_EXPAND_STEPS"] == "1" }
    /// 截图用：打开会话后滚动到顶部。
    static var scrollToTop: Bool { environment["DSH_SCROLL_TO_TOP"] == "1" }
    /// 截图用：启动后直接打开设置页。
    static var showSettings: Bool { environment["DSH_SETTINGS"] == "1" }
    /// 截图用：打开会话后自动引用最后一条助手消息。
    static var quoteDemo: Bool { environment["DSH_QUOTE"] == "1" }
    /// 截图用：不自动聚焦输入框（避免键盘挡住画面）。
    static var noFocus: Bool { environment["DSH_NO_FOCUS"] == "1" }
    /// 截图用：使用商店截图专用示例（多轮对话 / 图文 / 时间线标题）。
    static var storeShots: Bool { environment["DSH_STORE_SHOTS"] == "1" }
    /// 压测：打开会话后立刻连发 N 条消息（每条间隔 30ms），用来验证连发时的顺序与丢失。
    /// 只在演示模式生效。
    static var sendBurst: Int {
        guard let raw = environment["DSH_SEND_BURST"], let n = Int(raw), n > 0 else { return 0 }
        return min(n, 50)
    }
    /// 压测场景列表，语法见 `StressScenario`：`messages:400,images:120,steps:80`。
    /// 只在演示模式生效。
    static var stressScenarios: [StressScenario] { StressScenario.parse(environment["DSH_STRESS"]) }

    /// 模拟器用 `SIMCTL_CHILD_DSH_SERVER`，真机用 `DEVICECTL_CHILD_DSH_SERVER`，
    /// 由 simctl / devicectl 去掉前缀后注入进程环境。
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    private static func value(for key: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: key), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
