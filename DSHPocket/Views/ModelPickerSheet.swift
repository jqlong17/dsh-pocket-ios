// ModelPickerSheet

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


struct ModelPickerSheet: View {
    @Bindable var model: ConnectionModel
    @Environment(\.dismiss) private var dismiss
    @State private var languageRevision = 0

    var body: some View {
        NavigationStack {
            List {
                if model.modelGroups.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L10n.t("正在加载模型…")).foregroundStyle(.secondary)
                    }
                }
                ForEach(model.modelGroups) { group in
                    Section(group.name) {
                        ForEach(group.models) { option in
                            Button {
                                Task {
                                    await model.selectModel(option)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.name).foregroundStyle(.primary)
                                        Text(option.model)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if model.selectedModelLabel == option.name {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.t("选择模型"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("取消")) { dismiss() }
                }
            }
            .task {
                if model.modelGroups.isEmpty { await model.loadModelCatalog() }
            }
        }
        .id(languageRevision)
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageChanged)) { _ in
            languageRevision &+= 1
        }
    }
}
