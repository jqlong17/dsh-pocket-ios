import Foundation

/// 取图的请求形状与降级规则。
///
/// 客户端会带上期望最大边，服务端支持就按需缩放；不支持会忽略这个字段，行为与以前一致。
public enum ImageFetchPolicy {
    public static let thumbnailMaxPixel = 640

    /// 全屏/保存用的最大边。
    ///
    /// 为什么是函数而不是常量：DSHKit 是纯逻辑层，不能读 UIScreen。
    /// 固定 2048 在 iPhone Pro Max（长边 2868）上会被放大 1.4 倍——截图里的文字直接糊。
    /// 由调用方传入屏幕长边，取「屏幕值」与「2048 下限」的较大者：
    /// - 大屏（2868）→ 2868，1:1 不放大
    /// - 小屏（1200）→ 2048，留余量，避免外接显示器或放大查看时糊
    public static func fullMaxPixel(screenLongSide: Int) -> Int {
        max(screenLongSide, 2048)
    }
    /// 超过这个大小的附件，高清只在用户点开时按需拉。
    public static let oversizedBytes = 4 * 1024 * 1024

    /// `session/attachment` 的请求体。
    public static func requestArgs(sessionId: String, attachment: [String: Any], maxPixel: Int) -> [String: Any] {
        [
            "sessionId": sessionId,
            "attachment": attachment,
            "maxPixel": maxPixel
        ]
    }

    public static func shouldFetchFullLazily(bytes: Int) -> Bool {
        bytes > oversizedBytes
    }
}
