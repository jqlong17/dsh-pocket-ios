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
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var toast: String?

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
                          preview: SharePreview("图片", image: Image(uiImage: image))) {
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
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(.black.opacity(0.45), in: Circle())
    }

    private func saveToAlbum() {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                toast = success ? "已保存到相册" : "保存失败：\(error?.localizedDescription ?? "未知错误")"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { toast = nil }
            }
        }
    }
}
