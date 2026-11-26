// DirectoryPickerView

import SwiftUI
import DSHKit

/// 在手机上浏览 Mac 的目录，选一个已存在的文件夹加成工作区。
///
/// 设计取舍：iOS 拿不到 Mac 的文件系统，插件只提供「只读列子目录」，
/// 所以这里是**逐层进入**而不是系统文件选择器；进错目录可以点左上角返回。
struct DirectoryPickerView: View {
    @Bindable var model: ConnectionModel
    /// 选好后回调（路径 + 用户起的名字，名字为空表示用目录名）。
    let onPick: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var listing: DirectoryListing?
    @State private var path: String?
    @State private var errorText: String?
    @State private var loading = false
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Group {
                if loading && listing == nil {
                    ProgressView(L10n.t("正在读取目录…"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let listing {
                    List {
                        if let errorText {
                            Section {
                                Text(errorText).font(.caption).foregroundStyle(.red)
                            }
                        }
                        Section {
                            // 名称：默认空 = 用目录名；填了就改名
                            TextField(L10n.t("名称（可留空，默认用目录名）"), text: $name)
                        } header: {
                            Text(L10n.t("工作区名称"))
                        }
                        Section {
                            if let parent = listing.parent {
                                Button {
                                    Task { await load(parent) }
                                } label: {
                                    Label(L10n.t("上一级"), systemImage: "arrow.up.left")
                                }
                            }
                            ForEach(listing.dirs) { dir in
                                Button {
                                    Task { await load(dir.path) }
                                } label: {
                                    HStack {
                                        Image(systemName: "folder").foregroundStyle(.tint)
                                        Text(dir.name).foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            if listing.dirs.isEmpty {
                                Text(L10n.t("这个目录下没有子目录")).font(.caption).foregroundStyle(.secondary)
                            }
                        } header: {
                            Text(listing.path).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.questionmark").font(.largeTitle).foregroundStyle(.secondary)
                        Text(errorText ?? L10n.t("没读到目录")).font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(L10n.t("选择文件夹"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("用这个目录")) {
                        guard let listing else { return }
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onPick(listing.path, trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                    .disabled(listing == nil)
                }
            }
            .task { await load(path) }
        }
    }

    private func load(_ target: String?) async {
        loading = true
        errorText = nil
        do {
            let result = try await model.listDirectories(at: target)
            listing = result
            path = result.path
            name = ""
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}
