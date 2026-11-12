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
    @Environment(\.scenePhase) private var scenePhase
    @State private var languageRevision = 0
    @State private var showingAppSettings = false
    var body: some View {
        NavigationStack(path: $model.navigationPath) {
            Group {
                if model.isConnected {
                    ConnectedView(model: model)
                } else {
                    ConnectView(model: model)
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
                model.installSessionActionProviders()
                model.installNetworkWatcher()
                model.installNotificationProviders()
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
            guard phase == .active, model.isConnected else { return }
            Task { await model.loadSessions(silently: true) }
        }
        .task(id: model.isConnected) {
            // 周期刷新会话列表，识别"其他会话跑完了"（完成提醒的红点/通知）。
            guard model.isConnected, !model.isDemoMode else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if Task.isCancelled { break }
                await model.loadSessions(silently: true)
            }
        }
    }
}
