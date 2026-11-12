import SwiftUI

/// 动画门闸：减少动态效果时一律不播放。
public enum MotionPolicy {
    public static func animation(_ animation: Animation?, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
