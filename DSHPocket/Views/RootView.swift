// RootView

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


struct RootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: ConnectionModel
    /// 导航路径属于会话列表场景：单独持有状态对象才能取可写绑定。
    @Bindable var sessionStore: SessionStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var languageRevision = 0
    @State private var showingAppSettings = false
    var body: some View {
        NavigationStack(path: $sessionStore.navigationPath) {
            Group {
                // 三态：还没确定（占位）→ 已连接（列表）→ 确定未连接（连接页）。
                // 中间态不可省：直接用 isConnected 会在启动瞬间渲染完整连接页（含扫码引导），
                // 恢复完成后才切走，用户看到「闪一下连接页」。
                if !model.connection.hasFinishedRestore {
                    LaunchPlaceholder()
                } else if model.connection.isConnected {
                    ConnectedView(model: model)
                } else {
                    ConnectView(model: model, connection: model.connection)
                }
            }
            .navigationTitle("DSH Pocket")
            .navigationBarTitleDisplayMode(.inline)
            // 系统「减少动态效果」写入统一门闸，模型层的 withAnimation 也跟着关。
            .onAppear {
                PocketMotion.reduceMotion = reduceMotion
                // 诊断数据源装配一次（幂等）：诊断不反向依赖模型，只能由入口注入。
                model.installDiagnosticsProviders()
                model.installQuestionProviders()
                model.installSessionAPIProviders()
                model.installNetworkWatcher()
                startRestoreWatchdog()
            }
            .onChange(of: reduceMotion) { _, value in PocketMotion.reduceMotion = value }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAppSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(L10n.t("设置"))
                }
            }
            .sheet(isPresented: $showingAppSettings) { AppSettingsSheet(model: model) }
            .id(languageRevision)
        }
        .tint(Color(red: 0.08, green: 0.48, blue: 0.37))
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageChanged)) { _ in
            languageRevision &+= 1
        }
        .task { await model.restoreConnection() }
        .onAppear {
#if DEBUG
            if DebugLaunch.showSettings { showingAppSettings = true }
#endif
        }
        .onChange(of: scenePhase) { _, phase in
            model.isAppActive = (phase == .active)
            // 回到前台只静默刷新列表，不自动切换网络，避免打断当前会话。
            guard phase == .active, model.connection.isConnected else { return }
            Task { await model.loadSessions(silently: true) }
        }
        .task(id: model.connection.isConnected) {
            // 周期刷新会话列表，识别"其他会话跑完了"（完成提醒的红点/通知）。
            guard model.connection.isConnected, !model.isDemoMode else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if Task.isCancelled { break }
                await model.loadSessions(silently: true)
            }
        }
    }

    /// 恢复超时兜底：`fetchSessions` 可能因网络问题长时间挂起，
    /// 没有兜底就会停在没有任何文字与转圈的占位页——用户只会觉得 App 死了。
    /// 超时不是放弃恢复，`restoreConnection` 仍在后台跑，完成时会自然切换页面。
    private func startRestoreWatchdog() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !model.connection.hasFinishedRestore else { return }
            model.connection.hasFinishedRestore = true
            model.recordDiagnostic("启动恢复超时 2 秒，先显示界面")
        }
    }
}
