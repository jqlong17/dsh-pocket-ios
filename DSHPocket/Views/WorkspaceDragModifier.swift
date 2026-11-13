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
                // 用 onDrag/onDrop 而不是 draggable/dropDestination：
                // 在 List 行里后者常被行自身的手势吃掉，能拖起但放不下（实测）。
                .onDrag {
                    dragging = groupId
                    return NSItemProvider(object: groupId as NSString)
                } preview: {
                    Text(L10n.t("移动工作区"))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                }
                .onDrop(of: [.text], delegate: WorkspaceDropDelegate(
                    targetId: groupId,
                    dragging: $dragging,
                    onDrop: onDrop
                ))
        } else {
            content
        }
    }
}

/// 把拖动的组头放到目标组头上。
///
/// `onDrop` 的 delegate 形态比 `dropDestination` 的闭包更可控：
/// 能拿到拖动中的 id（存在 `dragging` 里）并在 `performDrop` 时才提交。
private struct WorkspaceDropDelegate: DropDelegate {
    let targetId: String
    @Binding var dragging: String?
    let onDrop: (String, String) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }

    func performDrop(info: DropInfo) -> Bool {
        guard let from = dragging, from != targetId else { return false }
        dragging = nil
        onDrop(from, targetId)
        return true
    }

    func dropExited(info: DropInfo) {}
}
