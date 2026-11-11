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
    @State private var image: UIImage?
    @State private var failed = false
    @State private var showsPreview = false

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
            if let image { FullscreenImageViewer(image: image) }
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
            let key = "md:" + url.absoluteString
            if let cached = ImageMemory.shared.image(forKey: key) { image = cached; return }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                      let loaded = ImageMemory.thumbnail(data: data) else {
                    failed = true
                    return
                }
                ImageMemory.shared.store(loaded, forKey: key)
                image = loaded
            } catch {
                failed = true
            }
        }
        .onDisappear { image = nil }
    }
}
