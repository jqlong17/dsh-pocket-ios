// QRScannerView

import SwiftUI
import Security
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
import Vision


/// 扫二维码：相机实时扫 + 从相册导入两种方式。
///
/// 为什么需要相册导入：服务器场景（DSH 装在云上）的配对码是**别人发过来的图片**——
/// 可能在微信里、可能是终端生成的 PNG，人不在二维码前面，只能存图再选。
/// 原来的实现只有实时相机，那种图根本没法用（2026-11-15 用户反馈）。
struct QRScannerView: View {
    let onCode: (String) -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var decodingPhoto = false
    @State private var photoError: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            cameraLayer
            importBar
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await decodeQRCode(from: item) }
        }
        .alert(L10n.t("没能识别出二维码"), isPresented: Binding(
            get: { photoError != nil },
            set: { if !$0 { photoError = nil } }
        )) {
            Button(L10n.t("好"), role: .cancel) { photoError = nil }
        } message: {
            Text(photoError ?? "")
        }
    }

    // MARK: - 相机

    @ViewBuilder
    private var cameraLayer: some View {
        if DataScannerViewController.isSupported {
            if DataScannerViewController.isAvailable {
                PocketCodeScanner(onCode: onCode).ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView(
                    L10n.t("相机暂不可用"),
                    systemImage: "camera.fill",
                    description: Text(L10n.t("请在设置中允许 DSH Pocket 使用相机；也可以从相册选一张二维码图片。"))
                )
            }
        } else {
            ContentUnavailableView(
                L10n.t("此设备不支持实时扫码"),
                systemImage: "qrcode",
                description: Text(L10n.t("可以从相册选一张二维码图片，或手动输入地址。"))
            )
        }
    }

    // MARK: - 相册导入

    private var importBar: some View {
        VStack(spacing: 8) {
            PhotosPicker(
                selection: $photoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack(spacing: 8) {
                    if decodingPhoto {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "photo.on.rectangle")
                    }
                    Text(decodingPhoto ? L10n.t("识别中…") : L10n.t("从相册选二维码图片"))
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .foregroundStyle(.white)
                .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(decodingPhoto)
            .padding(.horizontal, 20)
            .accessibilityIdentifier("photo-picker-qr")

            Text(L10n.t("服务器上的配对码常在图片里，拍照存下来再从这里选"))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.bottom, 22)
    }

    /// 从相册图片里解出二维码内容。
    ///
    /// 用 Vision 而不是 CIDetector：CIQRCodeDetector 对**截图里的小二维码**
    /// 和带缩放的图经常解不出来，Vision 的成功率高得多，且能直接给 payload 字符串。
    private func decodeQRCode(from item: PhotosPickerItem) async {
        decodingPhoto = true
        defer {
            decodingPhoto = false
            photoItem = nil   // 允许再次选同一张
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let cgImage = image.cgImage else {
            photoError = L10n.t("这张图片读不出来，换一张再试。")
            return
        }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            photoError = L10n.t("识别失败：") + (error.localizedDescription)
            return
        }

        let payload = (request.results ?? [])
            .compactMap { $0 as? VNBarcodeObservation }
            .compactMap { $0.payloadStringValue }
            .first
        guard let payload, !payload.isEmpty else {
            photoError = L10n.t("这张图里没找到二维码。确认是完整的配对二维码截图，别裁掉边角。")
            return
        }
        onCode(payload)
    }
}
