import SwiftUI

/// 动画的统一出口。
///
/// 系统开了「减少动态效果」时，所有动画返回 nil —— 直接切换、不播放。
/// 视图都从 `PocketMotion.animation(_:)` 取动画，不要在别处直接写 `withAnimation(.easeInOut…)`。
public enum PocketMotion {
    /// 由根视图根据系统设置写入；模型层也会用到，所以用静态值而不是环境键。
    public static var reduceMotion = false

    /// 需要动画时返回传入的动画，减少动态时返回 nil。
    ///
    /// 这段门闸原先放在 DSHKit 的 `MotionPolicy` 里，导致纯逻辑层 import SwiftUI；
    /// 它没有任何判断逻辑、只是 UI 类型透传，属于 UI 层，故内联到这里（spec/11）。
    public static func animation(_ animation: Animation?) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// 常用时长，短、不拖沓。
    public static var quick: Animation { .easeInOut(duration: 0.18) }
    public static var standard: Animation { .easeInOut(duration: 0.22) }

    /// 展开/折叠（过程行、问答卡这类原地长高的容器）。
    ///
    /// 比 quick 再快一档：用户在点的那一刻已经在看内容了，
    /// 0.22 秒的等待会被感知成「点了才慢慢出来」。0.16 足够遮住高度跳变。
    public static var disclosure: Animation { .easeInOut(duration: 0.16) }
}
