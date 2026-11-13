// WorkspaceDragModifier

import SwiftUI

/// 给会话列表的工作区分组标题加「长按拖动换顺序」。
///
/// 为什么不用 `ForEach.onMove`：会话列表是「分组 → 会话」的嵌套结构，
/// `onMove` 作用在直接子项上（会变成组内排会话），而不是排组本身。
/// `draggable` + `dropDestination` 能精确表达「拖这个组头，放到那个组头上」。
struct WorkspaceDragModifier: ViewModifier {
    let groupId: String
    let isDraggable: Bool
    @Binding var dragging: String?
    let onDrop: (String, String) -> Void

    func body(content: Content) -> some View {
        if isDraggable {
            content
                .draggable(groupId) {
                    // 拖动时的小预览：只显示一个标题条，不用整行（整行太大挡住落点）。
                    Text(L10n.t("移动工作区"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let from = items.first else { return false }
                    dragging = nil
                    onDrop(from, groupId)
                    return true
                } isTargeted: { _ in }
                .onAppear { dragging = nil }
        } else {
            content
        }
    }
}
