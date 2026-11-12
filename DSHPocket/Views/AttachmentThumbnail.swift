// AttachmentThumbnail

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


/// 会话里的图片（用户发的 / 工具结果里的），按 attachmentId 读取电脑端附件。
struct AttachmentThumbnail: View {
    let ref: PocketImageRef
    @Bindable var model: ConnectionModel
    var size: CGFloat = 140
    @State private var image: UIImage?
    @State private var failed = false
    /// 点开全屏的上下文。用 item 而不是「布尔 + 数据」两个状态：
    /// 后者在 SwiftUI 里存在时序竞争——弹窗读到的可能还是空的旧数组，表现为黑屏。
    @State private var previewContext: PreviewContext?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .tertiarySystemFill))
                    VStack(spacing: 4) {
                        Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                        Text(L10n.t("图片加载失败")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .tertiarySystemFill))
                    ProgressView()
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { openPreview() }
        .accessibilityElement()
        .accessibilityLabel(AccessibilityLabels.attachment(index: nil, total: nil))
        .accessibilityAddTraits(.isButton)
        .fullScreenCover(item: $previewContext) { context in
            FullscreenImageViewer(entries: context.entries, startIndex: context.startIndex)
        }
        .task {
            if image == nil {
                image = await model.loadImage(ref)
                if image == nil { failed = true }
            }
        }
        .onDisappear { image = nil }
    }

    /// 点开全屏：把整组图连同起始位置一起塞进 context 再弹。
    ///
    /// 为什么不先写两个 @State 再置 bool：SwiftUI 会在同一个更新周期里读它们，
    /// 曾出现弹窗拿到空数组 → 全屏黑屏、第二次点才正常（实测）。
    private func openPreview() {
        guard let image else { return }
        let key = ImageSourceKey.attachment(ref.attachmentId)
        var entries = model.conversationImageEntries
        if let index = entries.firstIndex(where: { $0.id == key }) {
            entries[index].preview = image
            previewContext = PreviewContext(entries: entries, startIndex: index)
        } else if let single = model.fullscreenEntry(for: ref, preview: image) {
            previewContext = PreviewContext(entries: [single], startIndex: 0)
        }
    }

    /// 全屏上下文：一组图 + 从哪张开始。`id` 让每次点击都触发一次全新的呈现。
    struct PreviewContext: Identifiable {
        let id = UUID()
        let entries: [FullscreenEntry]
        let startIndex: Int
    }
}
