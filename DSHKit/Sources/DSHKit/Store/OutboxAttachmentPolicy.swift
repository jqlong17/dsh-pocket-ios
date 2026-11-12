import Foundation

/// 断网时图片要不要跟着排队、能排多少。
///
/// 图片是几十兆级别的数据，必须有硬上限，否则发件箱会把手机塞满。
public enum OutboxAttachmentPolicy {
    /// 一条消息最多几张图，和选择器的上限一致。
    public static let maxImagesPerMessage = 9
    /// 发件箱里所有附件允许占用的总字节（50 MB）。
    public static let maxTotalBytes = 50 * 1024 * 1024

    /// 这条消息的附件是否值得排队：数量不超限，且单条总大小在允许范围内。
    public static func canHold(imageCount: Int, totalBytes: Int) -> Bool {
        guard imageCount > 0, imageCount <= maxImagesPerMessage else { return false }
        return totalBytes > 0 && totalBytes <= maxTotalBytes
    }

    /// 再加上这些字节后，发件箱总占用是否还在上限内。
    public static func fits(currentTotalBytes: Int, adding newBytes: Int) -> Bool {
        currentTotalBytes + newBytes <= maxTotalBytes
    }
}
