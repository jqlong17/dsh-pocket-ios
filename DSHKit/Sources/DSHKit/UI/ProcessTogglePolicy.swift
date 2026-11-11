import Foundation

/// 点开或收起「过程」时，界面该做什么。
///
/// 这是约定，不是对某次实现的复述。单测只依赖这个类型，不启动模拟器。
public struct ProcessTogglePlan: Equatable, Sendable {
    /// 这次是展开，而不是收起。
    public var opening: Bool
    /// 展开且正文还没拉过，才向电脑要这一组的详情。
    public var loadDetails: Bool
    /// 收起时丢掉正文。
    public var dropDetails: Bool
    /// 展开会把行撑高。为 false 时不要再跟着列表底部滚。
    public var followLatest: Bool
    /// 这段时间内，高度变化不得触发贴底。单位秒。0 表示不抑制。
    public var suppressAutoScroll: TimeInterval
    /// 为 true 时把过程行滚到视口顶部。约定是 false：上方的锚点要留在原地。
    public var scrollToRowTop: Bool

    public init(
        opening: Bool,
        loadDetails: Bool,
        dropDetails: Bool,
        followLatest: Bool,
        suppressAutoScroll: TimeInterval,
        scrollToRowTop: Bool
    ) {
        self.opening = opening
        self.loadDetails = loadDetails
        self.dropDetails = dropDetails
        self.followLatest = followLatest
        self.suppressAutoScroll = suppressAutoScroll
        self.scrollToRowTop = scrollToRowTop
    }

    /// - Parameters:
    ///   - isExpanded: 点下去之前，这一组是否已经展开。
    ///   - needsDetails: 这一组里是否还有没拉过正文的步骤。
    public static func make(isExpanded: Bool, needsDetails: Bool) -> ProcessTogglePlan {
        let opening = !isExpanded
        return ProcessTogglePlan(
            opening: opening,
            loadDetails: opening && needsDetails,
            dropDetails: !opening,
            followLatest: false,
            suppressAutoScroll: 1.2,
            scrollToRowTop: false
        )
    }
}
