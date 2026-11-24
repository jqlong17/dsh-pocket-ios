import Foundation
import CoreGraphics

/// 消息气泡的宽度上限。
///
/// 为什么是纯逻辑：气泡宽度取错会连带把整页撑宽——底部输入栏的发送按钮会被推出屏幕
/// （2026-11-24 多图消息真机反馈）。这个换算只有几个系数，但「哪些宽度要扣掉」必须能单测，
/// 不能靠截图回调。
///
/// 推导（以 iPhone 16 Pro 393pt 为例）：
///
/// ```
/// 393（屏宽）
///  - 32（列表内边距 padding()，左右各 16）
///  - 44（气泡左侧 Spacer(minLength: 44)，用户消息靠右对齐时留的空白）
///  = 317
/// ```
public enum BubbleWidthPolicy {
    /// 列表左右内边距之和（`ConversationView` 里 `.padding()` 的默认 16 × 2）。
    public static let listHorizontalPadding: CGFloat = 32
    /// 用户消息气泡左侧的最小留白（`HStack { Spacer(minLength: 44); 气泡 }`）。
    public static let bubbleLeadingGap: CGFloat = 44
    /// 宽屏（iPad / 横屏）下气泡列的宽度上限，与列表的 `maxWidth: 720` 对齐。
    public static let maxColumnWidth: CGFloat = 720
    /// 再窄也要留一点宽度，不能算出负数。
    public static let minimumBubbleWidth: CGFloat = 160

    /// - Parameters:
    ///   - containerWidth: 列表容器（`ScrollView`）量到的宽度；未测量时为 0。
    ///   - fallbackContainerWidth: 容器尚未测量时用的兜底宽度（iPhone 竖屏 393）。
    public static func maxBubbleWidth(containerWidth: CGFloat,
                                      fallbackContainerWidth: CGFloat = 393) -> CGFloat {
        let raw = (containerWidth.isFinite && containerWidth > 0) ? containerWidth : fallbackContainerWidth
        let column = min(raw, maxColumnWidth)
        return max(minimumBubbleWidth, column - listHorizontalPadding - bubbleLeadingGap)
    }
}
