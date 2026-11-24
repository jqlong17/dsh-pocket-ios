import Foundation
import CoreGraphics

/// 多图缩略图的换行规则（纯逻辑，UI 只负责按行渲染）。
///
/// 为什么需要：用户消息里的缩略图曾经放在一个 `HStack` 里，5 张 88pt 的图
/// 合计 464pt，超过 iPhone 一屏的内容宽（约 361pt）。`HStack` 对固定宽度子视图
/// 不会收缩，于是整页宽度被撑开、底部输入栏的发送按钮被推出屏幕（2026-11-24 真机反馈）。
///
/// 所以列数必须由**可用宽度**算出来，再按行切块渲染；这段计算是纯函数，边界（0 宽、
/// 负间距、极窄屏）都能单测，不依赖 SwiftUI 的布局时机。
public enum ThumbnailWrapLayout {
    /// 一行最多能放几个缩略图。
    ///
    /// - 至少返回 1：再窄也要显示（返回 0 会让图片永远不出现）。
    /// - `spacing` 为负按 0 处理，否则会算出比图更窄的列、列数虚高。
    /// - 非有限值（`nan` / `infinity`，通常来自尚未测量的 Geometry 宽度）按 1 处理。
    public static func columnsPerRow(availableWidth: CGFloat, itemSize: CGFloat, spacing: CGFloat) -> Int {
        guard itemSize.isFinite, itemSize > 0 else { return 1 }
        guard availableWidth.isFinite, availableWidth > 0 else { return 1 }
        let gap = (spacing.isFinite && spacing > 0) ? spacing : 0
        // n 张图占 n * itemSize + (n - 1) * gap = n * (itemSize + gap) - gap
        let perItem = itemSize + gap
        let count = Int(floor((availableWidth + gap) / perItem))
        return max(1, count)
    }

    /// 按可用宽度把元素切成若干行。
    ///
    /// 保持原顺序、不丢元素：行内顺序与输入一致，`rows.flatMap { $0 } == items`。
    public static func rows<T>(_ items: [T], availableWidth: CGFloat, itemSize: CGFloat, spacing: CGFloat) -> [[T]] {
        guard !items.isEmpty else { return [] }
        let columns = columnsPerRow(availableWidth: availableWidth, itemSize: itemSize, spacing: spacing)
        guard columns > 1 else { return items.map { [$0] } }
        var result: [[T]] = []
        result.reserveCapacity((items.count + columns - 1) / columns)
        var index = 0
        while index < items.count {
            let end = min(index + columns, items.count)
            result.append(Array(items[index..<end]))
            index = end
        }
        return result
    }
}
