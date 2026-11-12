// RemoteMarkdownImage

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


/// 消息 Markdown 渲染：交给 Textual（MarkdownUI 作者的新库，原生支持跨视图文本选择）。
/// 远程 Markdown 图片（相对 cwd 的本地截图通过 `api/file` 读取）。
struct RemoteMarkdownImage: View {
    let url: URL
    var caption: String? = nil
    /// 同会话的全部图片（按消息顺序）：点开后可以左右翻。
    var allImageURLs: [URL] = []
    @State private var image: UIImage?
    @State private var failed = false
    @State private var showsPreview = false
    /// 视图消失后的延迟清理任务（5 秒内回来就取消）。
    @State private var clearTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                HStack(spacing: 6) {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                    Text(L10n.t("图片加载失败")).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(width: 200, height: 72)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .tertiarySystemFill))
                    ProgressView()
                }
                .frame(width: 200, height: 120)
            }
        }
        .frame(maxWidth: 240)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { if image != nil { showsPreview = true } }
        .fullScreenCover(isPresented: $showsPreview) {
            // 有点开上下文就带上整组图，支持左右翻页；否则退化成单张。
            let urls = allImageURLs.isEmpty ? [url] : allImageURLs
            let index = urls.firstIndex(of: url) ?? 0
            let entries = urls.map { target in
                FullscreenEntry(
                    id: ImageSourceKey.remote(target),
                    source: RemoteURLByteSource(url: target),
                    // 只有当前这张已经解码过，其余页进来再拉（避免一次解码十几张）。
                    preview: target == url ? image : nil
                )
            }
            FullscreenImageViewer(entries: entries, startIndex: index)
        }
        .overlay(alignment: .bottomLeading) {
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                    .padding(6)
            }
        }
        .task {
            guard image == nil else { return }
            // 与附件图走同一条管线：缓存、降采样、并发去重都由 ImagePipeline 负责，
            // 这里只提供「怎么拿字节」。以前这条线自己缩到 640，导致全屏时是放大的缩略图。
            let source = RemoteURLByteSource(url: url)
            let loaded = await ImagePipeline.shared.image(
                source: source,
                tier: .thumbnail,
                maxPixel: CGFloat(ImageFetchPolicy.thumbnailMaxPixel)
            )
            if let loaded {
                image = loaded
            } else {
                failed = true
            }
        }
        .onAppear {
            // 重新出现在屏幕上：取消待执行的清理。
            clearTask?.cancel()
            clearTask = nil
        }
        .onDisappear {
            // 不立即清空：列表快速滑动时图片反复进出，立即清会一直看到占位图。
            // 5 秒足够覆盖「滑过去又滑回来」，也不会长期占着解码后的位图。
            clearTask?.cancel()
            clearTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                image = nil
            }
        }
    }
}
