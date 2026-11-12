// FullscreenImageViewer

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


/// 全屏图片查看：捏合/双击缩放、关闭、保存到相册、系统分享。
struct FullscreenImageViewer: View {
    /// 附件来源：有 ref 时会按需拉高清；没有就是纯本地图片。
    let ref: PocketImageRef?
    let model: ConnectionModel?
    @State private var image: UIImage
    @State private var loadingFull = false
    @State private var fullFailed = false
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var toast: String?

    init(image: UIImage) {
        self.ref = nil
        self.model = nil
        _image = State(initialValue: image)
    }

    /// 先用缩略图占位，打开后按需换成高清。
    init(ref: PocketImageRef, model: ConnectionModel, startingWith preview: UIImage) {
        self.ref = ref
        self.model = model
        _image = State(initialValue: preview)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in scale = min(max(lastScale * value, 1), 5) }
                        .onEnded { _ in lastScale = scale }
                )
                .onTapGesture(count: 2) {
                    withAnimation(PocketMotion.animation(.easeInOut(duration: 0.2))) {
                        scale = scale > 1 ? 1 : 2.5
                        lastScale = scale
                    }
                }
        }
        .overlay(alignment: .top) {
            HStack(spacing: 12) {
                Button { dismiss() } label: { circleIcon("xmark") }
                    .accessibilityLabel(L10n.t("关闭"))
                Spacer()
                ShareLink(item: Image(uiImage: image),
                          preview: SharePreview(L10n.t("图片"), image: Image(uiImage: image))) {
                    circleIcon("square.and.arrow.up")
                }
                Button { saveToAlbum() } label: { circleIcon("square.and.arrow.down") }
                    .accessibilityLabel(L10n.t("保存到相册"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .animation(PocketMotion.animation(.easeInOut(duration: 0.2)), value: toast)
        .statusBarHidden(true)
        .task {
            // 缩略图先顶上，高清到位后替换；失败就明说这是预览图。
            guard let ref, let model, !loadingFull else { return }
            loadingFull = true
            if let full = await model.loadFullImage(ref) {
                image = full
            } else {
                fullFailed = true
                toast = L10n.t("高清图没拉到，当前是预览图")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { toast = nil }
            }
            loadingFull = false
        }
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(.black.opacity(0.45), in: Circle())
    }

    private func saveToAlbum() {
        // 存相册要高清，不能把 640 的缩略图存进去。
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                toast = success ? L10n.t("已保存到相册") : "\(L10n.t("保存失败"))：\(error?.localizedDescription ?? L10n.t("未知错误"))"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { toast = nil }
            }
        }
    }
}
