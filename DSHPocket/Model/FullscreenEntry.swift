// FullscreenEntry

import UIKit
import DSHKit

/// 全屏里的一张图。
///
/// 为什么把「来源」和「预览图」放在一起：翻页时新的一页要先有东西显示（预览图），
/// 再异步换成高清。两者分属不同来源（URL / 附件 RPC），统一成 `ImageByteSource` 后
/// 全屏组件不需要知道图片从哪来。
struct FullscreenEntry: Identifiable {
    /// 稳定 id：翻页时靠它区分「哪一页已经加载过高清」。
    let id: String
    /// 高清来源；纯本地图（草稿预览）为 nil，不做二次加载。
    let source: ImageByteSource?
    /// 调用方已经拿到的图（缩略图或本地图），用于首帧立即显示。
    var preview: UIImage?

    init(id: String, source: ImageByteSource?, preview: UIImage?) {
        self.id = id
        self.source = source
        self.preview = preview
    }
}
