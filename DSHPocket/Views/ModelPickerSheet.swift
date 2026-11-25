// ModelPickerSheet

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


struct ModelPickerSheet: View {
    @Bindable var model: ConnectionModel
    @Environment(\.dismiss) private var dismiss
    @State private var languageRevision = 0
    /// 已点选、正在选推理强度的模型。nil 表示还在模型列表。
    @State private var pendingModel: ModelOption?

    var body: some View {
        NavigationStack {
            List {
                if let pending = pendingModel {
                    reasoningSection(for: pending)
                } else {
                    modelSection
                }
            }
            .navigationTitle(pendingModel?.name ?? L10n.t("选择模型"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("取消")) { dismiss() }
                }
            }
            .task {
                // 每次都刷新：模型清单取决于「现在连的是哪台 DSH」，
                // 只在为空时加载会出现「换了机器但列表还是旧的」（2026-11-25 反馈）。
                await model.loadModelCatalog()
            }
        }
        .id(languageRevision)
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageChanged)) { _ in
            languageRevision &+= 1
        }
    }

    @ViewBuilder
    private var modelSection: some View {
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
                        // 支持推理强度的模型：先进强度选择，避免「选了模型却落了默认强度」。
                        if option.hasReasoning {
                            pendingModel = option
                        } else {
                            Task {
                                await model.selectModel(option)
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.name).foregroundStyle(.primary)
                                HStack(spacing: 6) {
                                    Text(option.model)
                                    if option.hasReasoning {
                                        Text("·")
                                        Text(L10n.t("\(option.reasoningEfforts.count) 档推理"))
                                    }
                                }
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

    @ViewBuilder
    private func reasoningSection(for option: ModelOption) -> some View {
        Section {
            // 省略 reasoningEffort 就是「提供方默认」，所以这是一个真实可选档。
            Button {
                apply(option, effort: nil)
            } label: {
                reasoningRow(title: L10n.t("提供方默认"),
                             subtitle: option.defaultEffort == nil ? L10n.t("当前默认") : nil,
                             selected: false)
            }
            ForEach(option.reasoningEfforts) { effort in
                Button {
                    apply(option, effort: effort.id)
                } label: {
                    reasoningRow(title: effort.name,
                                 subtitle: effort.detail,
                                 selected: option.defaultEffort == effort.id)
                }
            }
        } header: {
            Text(L10n.t("推理强度"))
        } footer: {
            Text(L10n.t("档位由模型的提供方定义，各模型不同。选「提供方默认」则不指定。"))
        }
        Section {
            Button(L10n.t("返回模型列表")) { pendingModel = nil }
        }
    }

    private func reasoningRow(title: String, subtitle: String?, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.37))
            }
        }
    }

    private func apply(_ option: ModelOption, effort: String?) {
        Task {
            await model.selectModel(option, reasoningEffort: effort)
            dismiss()
        }
    }
}

