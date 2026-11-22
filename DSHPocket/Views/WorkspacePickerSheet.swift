// WorkspacePickerSheet

import SwiftUI
import DSHKit

/// 新建会话前选工作区。
///
/// 设计取舍：默认选中「上次用过的 / 默认工作区」，所以 90% 的情况只需点「创建」两下；
/// 想换工作区时才去列表里挑。这样既满足「能选」，又不给每次都加负担。
struct WorkspacePickerSheet: View {
    let workspaces: [PocketWorkspace]
    let preselectedId: String?
    let isLoading: Bool
    let onCancel: () -> Void
    let onCreate: (String?) -> Void

    @State private var selectedId: String?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(L10n.t("正在读取工作区…"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if workspaces.isEmpty {
                    // 读不到工作区时不挡住新建：直接走「不传 workspaceId」的旧行为。
                    VStack(spacing: 10) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.largeTitle).foregroundStyle(.secondary)
                        Text(L10n.t("没读到工作区列表"))
                            .font(.callout).foregroundStyle(.secondary)
                        Text(L10n.t("仍然可以建会话，会落在默认工作区"))
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 不用 List：List 的每一行会先吃掉一次点击（行高亮/选中态），
                    // 表现就是「第一次点没反应、第二次才勾上」，换 buttonStyle 也压不住。
                    // 这个列表最多十几项，不需要 List 的复用，用 LazyVStack 就够了。
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(workspaces) { workspace in
                                row(for: workspace)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedId = workspace.workspaceId }
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.t("新建会话"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("取消")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        creating = true
                        onCreate(effectiveSelection)
                    } label: {
                        if creating {
                            ProgressView()
                        } else {
                            Text(L10n.t("创建"))
                        }
                    }
                    .disabled(creating)
                }
            }
        }
        .presentationDetents([.medium, .large])
        // 数据是异步来的：弹窗时 isLoading 为真、workspaces 为空，
        // 那时算不出该选谁。所以三个时机都同步一次，而不是只在 onAppear。
        .onAppear { syncSelection() }
        .onChange(of: isLoading) { _, loading in if !loading { syncSelection() } }
        .onChange(of: preselectedId) { _, _ in syncSelection() }
    }

    private func row(for workspace: PocketWorkspace) -> some View {
        HStack(spacing: 12) {
            Image(systemName: effectiveSelection == workspace.workspaceId ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(effectiveSelection == workspace.workspaceId ? Color.accentColor : Color.secondary.opacity(0.4))
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(workspace.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if workspace.sessionCount > 0 {
                    Text(L10n.tf("%d 个会话", workspace.sessionCount))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// 真正生效的选中项：**算出来的，不依赖 sync 是否跑过**。
    ///
    /// 之前只靠 `syncSelection()` 写 `selectedId`，一旦预选 id 是个「已不在列表里的旧值」，
    /// 所有行都匹配不上，界面上就是「一个都没勾」——用户以为选不了，实际是选中了一个幽灵项。
    private var effectiveSelection: String? {
        if let selectedId, workspaces.contains(where: { $0.workspaceId == selectedId }) {
            return selectedId
        }
        return workspaces.first?.workspaceId
    }

    /// 选中项同步：优先预选值，其次列表第一项。
    ///
    /// 只在「当前选中不在列表里」时改写——用户已经手动选过的不能被覆盖。
    private func syncSelection() {
        guard !isLoading, !workspaces.isEmpty else { return }
        if let selectedId, workspaces.contains(where: { $0.workspaceId == selectedId }) { return }
        // 预选值必须在列表里才采用；否则退回第一项。
        // 「宁可勾错也不能没有勾」——没有勾时用户以为选不了。
        if let preselectedId, workspaces.contains(where: { $0.workspaceId == preselectedId }) {
            selectedId = preselectedId
        } else {
            selectedId = workspaces.first?.workspaceId
        }
    }
}
