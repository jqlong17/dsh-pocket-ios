// ImagePipeline

import SwiftUI
import DSHKit

/// 图片加载管线：内存 → 磁盘（仅缩略图，共 5 MB）→ 网络。
///
/// 三条规矩：
/// 1. 解码一律在后台，绝不在主线程动 CGImageSource；
/// 2. 同一个 key 并发只发一次网络请求；
/// 3. 缩略图写磁盘，冷启动能直接显示；高清只在内存，因为没必要长期占空间。
final class ImagePipeline {
    static let shared = ImagePipeline()

    enum Tier: String {
        case thumbnail
        case full
    }

    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let disk = ThumbnailDiskCache()

    private let fullCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 8
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    /// 取图。附件图与 Markdown 图共用这一条路径，差异只在 `source`。
    ///
    /// 分层规则：
    /// - `.thumbnail`：内存 → 磁盘 → 网络，解码到 640，磁盘留一份（5MB 预算）；
    /// - `.full`：只用内存缓存，解码到屏幕像素。**不写磁盘**——高清动辄 1MB，
    ///   存了会把 5MB 预算里的缩略图挤出去，反而让列表更慢。
    func image(source: ImageByteSource,
               tier: Tier,
               maxPixel: CGFloat) async -> UIImage? {
        let key = "\(tier.rawValue):\(source.cacheKey)"

        if let cached = memoryImage(key: source.cacheKey, tier: tier) { return cached }
        if tier == .thumbnail,
           let fromDisk = disk.read(ThumbnailCachePolicy.fileName(attachmentId: source.cacheKey,
                                                                  maxPixel: Int(maxPixel))) {
            ImageMemory.shared.store(fromDisk, forKey: source.cacheKey)
            return fromDisk
        }

        // 同一张图并发请求合并：滚动时不会为同一张图拉好几遍。
        lock.lock()
        if let existing = inFlight[key] {
            lock.unlock()
            return await existing.value
        }
        let task = Task<UIImage?, Never> { [weak self] in
            defer { self?.clearInFlight(key) }
            guard let data = try? await source.data(maxPixel: Int(maxPixel)) else { return nil }
            // 解码放到后台，避免大图首次显示卡主线程。
            let decodeStart = Date()
            guard let image = await Task.detached(priority: .utility, operation: {
                ImageMemory.thumbnail(data: data, maxPixel: maxPixel)
            }).value else { return nil }
            let decodeMs = Int(Date().timeIntervalSince(decodeStart) * 1000)
            self?.store(image, key: source.cacheKey, tier: tier, maxPixel: maxPixel)
            imageLog.info("decode key=\(source.cacheKey, privacy: .public) tier=\(tier.rawValue, privacy: .public) ms=\(decodeMs) px=\(Int(maxPixel))")
            return image
        }
        inFlight[key] = task
        lock.unlock()
        return await task.value
    }

    private func clearInFlight(_ key: String) {
        lock.lock()
        inFlight[key] = nil
        lock.unlock()
    }

    private func memoryImage(key: String, tier: Tier) -> UIImage? {
        switch tier {
        case .thumbnail:
            return ImageMemory.shared.image(forKey: key)
        case .full:
            return fullCache.object(forKey: key as NSString)
        }
    }

    private func store(_ image: UIImage, key: String, tier: Tier, maxPixel: CGFloat) {
        switch tier {
        case .thumbnail:
            ImageMemory.shared.store(image, forKey: key)
            disk.write(image,
                       name: ThumbnailCachePolicy.fileName(attachmentId: key, maxPixel: Int(maxPixel)))
        case .full:
            let cost = max(image.cgImage.map { $0.width * $0.height * 4 } ?? 1, 1)
            fullCache.setObject(image, forKey: key as NSString, cost: cost)
        }
    }

    /// 附件失效时清掉磁盘副本。
    func forget(cacheKey: String) {
        disk.removePrefix(cacheKey)
        fullCache.removeObject(forKey: cacheKey as NSString)
    }
}

/// 缩略图磁盘缓存：Caches 目录 + 5 MB 上限 + 最久未访问淘汰。
final class ThumbnailDiskCache {
    private let directory: URL?
    private let queue = DispatchQueue(label: "dsh-pocket.thumbnail-disk", qos: .utility)

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("dsh-pocket/thumbs", isDirectory: true)
        if let base {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        directory = base
    }

    func read(_ name: String) -> UIImage? {
        guard let url = directory?.appendingPathComponent(name),
              let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return UIImage(data: data)
    }

    func write(_ image: UIImage, name: String) {
        guard let directory, let data = image.jpegData(compressionQuality: 0.8) else { return }
        queue.async {
            try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
            self.evictIfNeeded(in: directory)
        }
    }

    func removePrefix(_ prefix: String) {
        guard let directory else { return }
        queue.async {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                     includingPropertiesForKeys: nil)) ?? []
            for file in files where file.lastPathComponent.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func evictIfNeeded(in directory: URL) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                 includingPropertiesForKeys: keys)) ?? []
        let entries = files.compactMap { url -> (name: String, bytes: Int, lastAccess: Date)? in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return (url.lastPathComponent, values?.fileSize ?? 0, values?.contentModificationDate ?? .distantPast)
        }
        for name in ThumbnailCachePolicy.evictions(entries: entries) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
