import Foundation

/// 进入一条会话时，界面该不该显示「加载中」。
///
/// 有缓存就直接显示内容，别再转圈等快照；没有缓存才显示加载态。
public struct ConversationOpenPlan: Equatable {
    /// true 表示这次进入不显示加载态（内容已在内存里）。
    public let skipLoadingState: Bool
    /// 这次进入的加载来源；不显示加载态时记为 cache。
    public let loadSource: String?

    public init(skipLoadingState: Bool, loadSource: String?) {
        self.skipLoadingState = skipLoadingState
        self.loadSource = loadSource
    }

    public static func make(cachedMessageCount: Int) -> ConversationOpenPlan {
        guard cachedMessageCount > 0 else {
            return ConversationOpenPlan(skipLoadingState: false, loadSource: nil)
        }
        return ConversationOpenPlan(skipLoadingState: true, loadSource: "cache")
    }
}
