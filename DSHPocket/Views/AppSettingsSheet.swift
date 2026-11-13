// AppSettingsSheet

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


struct AppSettingsSheet: View {
    @Bindable var model: ConnectionModel
    @AppStorage("dsh-pocket.session-list-mode") private var sessionListModeRaw = SessionListMode.timeline.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var languageRevision = 0
    /// 排序面板的上下文。用 item 而不是「bool + 数据」两个状态：
    /// 后者弹窗时读到的数据可能还是上一轮的空数组（SwiftUI 同一更新周期批量处理，
    /// 附件图黑屏那次也是这个原因）。
    @State private var reorderContext: ReorderContext?

    struct ReorderContext: Identifiable {
        let id = UUID()
        let workspaces: [PocketWorkspace]
        let failure: String?
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("语言")) {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            LanguageStore.shared.code = language
                        } label: {
                            HStack {
                                Text(language.title())
                                Spacer()
                                if LanguageStore.shared.code == language {
                                    Image(systemName: "checkmark").foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37))
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section(L10n.t("会话列表")) {
                    Picker(L10n.t("显示方式"), selection: $sessionListModeRaw) {
                        ForEach(SessionListMode.allCases) { mode in
                            Text(mode.title()).tag(mode.rawValue)
                        }
                    }
                }
                Section(L10n.t("工作区")) {
                    Button {
                        openReorder()
                    } label: {
                        HStack {
                            Text(L10n.t("调整工作区顺序"))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                Section(L10n.t("完成提醒")) {
                    Toggle(isOn: Binding(
                        get: { model.completionAlertsEnabled },
                        set: { _ in model.toggleCompletionAlerts() }
                    )) {
                        Text(L10n.t("完成提醒"))
                    }
                }
                Section("DSH Pocket") {
                    HStack {
                        Text(L10n.t("版本"))
                        Spacer()
                        Text(versionText).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.t("设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("完成")) { dismiss() }
                }
            }
            .sheet(item: $reorderContext) { context in
                WorkspaceReorderSheet(
                    workspaces: context.workspaces,
                    isDemo: model.isDemoMode,
                    failureReason: context.failure,
                    onRetry: { openReorder() },
                    onMove: { fromId, beforeId in
                        Task { await model.moveWorkspace(fromId, before: beforeId) }
                    },
                    onClose: { reorderContext = nil }
                )
            }
        }
        .id(languageRevision)
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageChanged)) { _ in
            languageRevision &+= 1
        }
    }

}

extension AppSettingsSheet {
    /// 打开排序面板。
    ///
    /// **优先用已有缓存**（新建会话/连接后预加载时拉到的），不重新拉：
    /// 这条 WebSocket 请求在设置页的上下文里不稳定，而缓存里的数据是可靠的。
    /// 只有缓存为空时才尝试加载，失败就给提示和重试按钮。
    fileprivate func openReorder() {
        Task {
            if model.workspaces.isEmpty {
                _ = await model.loadWorkspaces()
            }
            let ordered = WorkspaceParsing.orderedForPicker(model.workspaces, defaultId: nil)
            await MainActor.run {
                reorderContext = ReorderContext(workspaces: ordered,
                                                failure: model.lastWorkspaceLoadError)
            }
        }
    }
}
