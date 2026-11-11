import Foundation
import CoreGraphics

/// 用户位移之后要不要跟着贴底。
///
/// 原生语义：只有真正贴底才恢复跟随；手指在屏上时一律不抢。
public enum ScrollFollowAction: Equatable {
    /// 已经在底部：恢复跟随、清未读。
    case follow
    /// 用户把内容推出了底部：停止跟随。
    case stopFollow
    /// 内容变高但仍在跟随：补一次贴底。
    case pinToBottom
    /// 什么都不做。
    case keep
}

public enum ScrollFollowPolicy {
    /// 离底多少点以内算「在底部」。原生是贴着底，不是「附近」。
    public static let bottomThreshold: CGFloat = 8

    public static func isAtBottom(distanceFromBottom: CGFloat) -> Bool {
        distanceFromBottom <= bottomThreshold
    }

    /// 滚动几何变化时的统一判定。
    public static func action(distanceFromBottom: CGFloat,
                              isDragging: Bool,
                              followsLatest: Bool) -> ScrollFollowAction {
        if isAtBottom(distanceFromBottom: distanceFromBottom) { return .follow }
        if isDragging { return .stopFollow }
        return followsLatest ? .pinToBottom : .keep
    }

    /// 是否允许程序化贴底。手指在屏上一律不允许，包括「强制」请求。
    public static func canAutoScroll(isDragging: Bool, followsLatest: Bool, force: Bool) -> Bool {
        if isDragging { return false }
        return force || followsLatest
    }
}
