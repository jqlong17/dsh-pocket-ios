import SwiftUI
import DSHKit

/// 动画的统一出口。
///
/// 系统开了「减少动态效果」时，所有动画返回 nil —— 直接切换、不播放。
/// 视图都从 `PocketMotion.animation(_:)` 取动画，不要在别处直接写 `withAnimation(.easeInOut…)`。
public enum PocketMotion {
    /// 由根视图根据系统设置写入；模型层也会用到，所以用静态值而不是环境键。
    public static var reduceMotion = false

    /// 需要动画时返回传入的动画，减少动态时返回 nil。
    public static func animation(_ animation: Animation?) -> Animation? {
        MotionPolicy.animation(animation, reduceMotion: reduceMotion)
    }

    /// 常用时长，短、不拖沓。
    public static var quick: Animation { .easeInOut(duration: 0.18) }
    public static var standard: Animation { .easeInOut(duration: 0.22) }
}
