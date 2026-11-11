// ImageMemory

import SwiftUI
import Security
import Textual
import DSHKit
import VisionKit
import AVFoundation
import Observation
import PhotosUI
import UIKit
import Photos
import os
import AudioToolbox
import ImageIO
import UserNotifications


/// 聊天图片只保留缩略图，并给缓存加上限。原图解码后一张截图就可能几十 MB，
/// 反复进出会话时如果视图没立刻释放，无上限缓存会把内存顶到几百 MB。
final class ImageMemory: NSObject, NSCacheDelegate {
    static let shared = ImageMemory()
    static let thumbnailMaxPixel: CGFloat = 640

    private let cache = NSCache<NSString, CachedImage>()
    private let lock = NSLock()
    private var retainedBytes = 0
    private var retainedCount = 0

    private override init() {
        super.init()
        cache.countLimit = 48
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.delegate = self
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)?.image
    }

    func store(_ image: UIImage, forKey key: String) {
        let cost = max(image.cgImage.map { $0.width * $0.height * 4 } ?? 1, 1)
        cache.setObject(CachedImage(image: image, cost: cost), forKey: key as NSString, cost: cost)
        lock.lock()
        retainedBytes += cost
        retainedCount += 1
        lock.unlock()
    }

    func stats() -> (count: Int, bytes: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (retainedCount, retainedBytes)
    }

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let box = obj as? CachedImage else { return }
        lock.lock()
        retainedBytes = max(0, retainedBytes - box.cost)
        retainedCount = max(0, retainedCount - 1)
        lock.unlock()
    }

    /// 用 ImageIO 直接出缩略图，避免先把整张原图解进内存。
    static func thumbnail(data: Data, maxPixel: CGFloat = thumbnailMaxPixel) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

private final class CachedImage: NSObject {
    let image: UIImage
    let cost: Int
    init(image: UIImage, cost: Int) {
        self.image = image
        self.cost = cost
    }
}
