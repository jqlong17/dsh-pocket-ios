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
    @AppStorage("dsh-pocket.session-list-mode") private var sessionListModeRaw = SessionListMode.grouped.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var languageRevision = 0

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
        }
        .id(languageRevision)
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageChanged)) { _ in
            languageRevision &+= 1
        }
    }
}
