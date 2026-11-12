import Foundation

/// 取图的请求形状与降级规则。
///
/// 客户端会带上期望最大边，服务端支持就按需缩放；不支持会忽略这个字段，行为与以前一致。
public enum ImageFetchPolicy {
    public static let thumbnailMaxPixel = 640
    public static let fullMaxPixel = 2048
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
