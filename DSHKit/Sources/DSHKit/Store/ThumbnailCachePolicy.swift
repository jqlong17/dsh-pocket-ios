import Foundation

/// 缩略图磁盘缓存：只留很小一份，超出就按最久未访问淘汰。
public enum ThumbnailCachePolicy {
    /// 磁盘总量上限。移动端缩略图不需要更多。
    public static let maxTotalBytes = 5 * 1024 * 1024

    /// 单个缓存文件的键（attachmentId + 尺寸），保证不同尺寸互不覆盖。
    public static func fileName(attachmentId: String, maxPixel: Int) -> String {
        let safe = attachmentId.replacingOccurrences(of: "/", with: "_")
        return "\(safe)-\(maxPixel).jpg"
    }

    /// 给出当前缓存条目，返回应该删掉的（按最久未访问优先）。
    public static func evictions(entries: [(name: String, bytes: Int, lastAccess: Date)]) -> [String] {
        let total = entries.reduce(0) { $0 + $1.bytes }
        guard total > maxTotalBytes else { return [] }
        var remaining = total
        var doomed: [String] = []
        for entry in entries.sorted(by: { $0.lastAccess < $1.lastAccess }) {
            guard remaining > maxTotalBytes else { break }
            doomed.append(entry.name)
            remaining -= entry.bytes
        }
        return doomed
    }
}
