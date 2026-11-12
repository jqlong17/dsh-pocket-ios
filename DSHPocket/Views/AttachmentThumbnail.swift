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
    @State private var showsPreview = false

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
        .onTapGesture { if image != nil { showsPreview = true } }
        .accessibilityElement()
        .accessibilityLabel(AccessibilityLabels.attachment(index: nil, total: nil))
        .accessibilityAddTraits(.isButton)
        .fullScreenCover(isPresented: $showsPreview) {
            if let image {
                // 有 ref 就按需拉高清；缩略图只是占位。
                FullscreenImageViewer(ref: ref, model: model, startingWith: image)
            }
        }
        .task {
            if image == nil {
                image = await model.loadImage(ref)
                if image == nil { failed = true }
            }
        }
        .onDisappear { image = nil }
    }
}
