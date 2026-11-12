// LaunchPlaceholder

import SwiftUI

/// 启动恢复期间的占位。
///
/// 为什么需要它：`RootView` 原先只有「已连接 / 未连接」两态，启动瞬间 `isConnected == false`，
/// 于是先渲染完整连接页（含扫码引导），等恢复完成才切到会话列表——用户看到「闪一下连接页」。
/// 这个占位承接那几百毫秒，让「启动 → 列表」在视觉上没有中间页面。
///
/// 设计取舍：
/// - **不放文字**（「恢复中」「加载中」都会把技术状态暴露给用户，放大等待感）；
/// - **不放转圈**（ProgressView 暗示「在等网络」，而多数情况几百毫秒就完成，反而显得慢）；
/// - 背景用 `systemBackground`，与连接页、会话列表一致，过渡不会有第二次闪烁。
struct LaunchPlaceholder: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(PocketChrome.brandText.opacity(0.55))
        }
        .accessibilityHidden(true)
    }
}
