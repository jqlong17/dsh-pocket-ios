// WorkspaceReorderSheet

import SwiftUI
import DSHKit

/// 调整工作区顺序。
///
/// 为什么单独开一个面板，而不是在会话列表里直接拖分组头：
/// 会话列表是「分组 → 会话」的嵌套 `ForEach`，`onMove` 只能作用在直接子项上；
/// 而 `draggable`/`onDrag` 在 List 行里会和折叠用的 tap、以及 List 自身的滚动打架，
/// 实测「拖不起来 / 拖起放不下 / 连按住都没反应」三种表现。
///
/// 这里用单层 `List` + `ForEach.onMove`：拖动重排是 UIKit 表格的原生实现，
/// 手势由系统接管，不存在冲突。代价是多一次点击（分组头长按 → 调整顺序）。
struct WorkspaceReorderSheet: View {
    let workspaces: [PocketWorkspace]
    let isDemo: Bool
    /// 加载失败的具体原因（空列表时显示，便于定位而不是只说「没读到」）。
    let failureReason: String?
    /// 空列表时的重试回调（首次握手失败很常见，给用户一个手动重试的按钮）。
    let onRetry: () -> Void
    let onMove: (_ fromId: String, _ beforeId: String?) -> Void
    let onClose: () -> Void

    @State private var items: [PocketWorkspace]

    init(workspaces: [PocketWorkspace],
         isDemo: Bool = false,
         failureReason: String? = nil,
         onRetry: @escaping () -> Void = {},
         onMove: @escaping (_ fromId: String, _ beforeId: String?) -> Void,
         onClose: @escaping () -> Void) {
        self.workspaces = workspaces
        self.isDemo = isDemo
        self.failureReason = failureReason
        self.onRetry = onRetry
        self.onMove = onMove
        self.onClose = onClose
        _items = State(initialValue: workspaces)
    }

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    // 空面板是「什么都看不到」的体验灾难，明确说清楚为什么空。
                    ContentUnavailableView(
                        isDemo ? L10n.t("演示模式没有工作区") : L10n.t("没读到工作区列表"),
                        systemImage: "square.stack.3d.up.slash",
                        description: Text(isDemo
                            ? L10n.t("连上电脑后才有真实工作区")
                            : (failureReason ?? L10n.t("先回会话列表点一下「+」，工作区加载一次后再进来")))
                    )
                    .listRowSeparator(.hidden)
                    if !isDemo {
                        Button(L10n.t("重试")) { onRetry() }
                            .listRowSeparator(.hidden)
                    }
                }
                ForEach(items) { workspace in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workspace.title).font(.body)
                            Text(workspace.path)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                    }
                }
                .onMove { indices, newOffset in
                    let moving = indices.map { items[$0] }
                    items.move(fromOffsets: indices, toOffset: newOffset)
                    // 一次性提交：把每个被移动项的新位置算成「插到谁之前」。
                    guard let first = moving.first,
                          let currentIndex = items.firstIndex(where: { $0.workspaceId == first.workspaceId })
                    else { return }
                    let beforeId = currentIndex + 1 < items.count ? items[currentIndex + 1].workspaceId : nil
                    onMove(first.workspaceId, beforeId)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(L10n.t("调整工作区顺序"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("完成")) { onClose() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // @State 的 initialValue 只取一次；参数变化时同步，避免拿到旧数组。
        .onChange(of: workspaces.count) { _, _ in items = workspaces }
    }
}
