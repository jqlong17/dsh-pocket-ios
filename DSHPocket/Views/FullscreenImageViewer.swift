// FullscreenImageViewer

import SwiftUI
import DSHKit
import UIKit
import Photos
import ImageIO

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

struct FullscreenImageViewer: View {
    @State private var entries: [FullscreenEntry]
    @State private var index: Int
    /// 已加载的高清图，按 entry.id 存。只保留访问过的页，翻走后不主动清（返回时还要用）。
    @State private var loaded: [String: UIImage] = [:]
    @State private var loadingIds: Set<String> = []
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var toast: String?

    /// 纯本地图（草稿图预览等）：单张，不翻页。
    init(image: UIImage) {
        let entry = FullscreenEntry(id: "local", source: nil, preview: image)
        _entries = State(initialValue: [entry])
        _index = State(initialValue: 0)
    }

    /// 单张附件（有 ref 时按需拉高清）。
    init(ref: PocketImageRef, model: ConnectionModel, startingWith preview: UIImage) {
        let source = AttachmentByteSource(
            attachmentId: ref.attachmentId,
            sessionId: model.sessionStore.selected?.sessionId ?? "",
            requestJSON: ref.requestJSON,
            knownBytes: ref.bytes,
            rpc: { [weak model] method, args in
                guard let model else { throw ConnectionError.invalidURL("") }
                return try await model.rpcClient.rpcAdapted(method, args: args)
            }
        )
        let entry = FullscreenEntry(id: ImageSourceKey.attachment(ref.attachmentId),
                                    source: source, preview: preview)
        _entries = State(initialValue: [entry])
        _index = State(initialValue: 0)
    }

    /// 多张图翻页。`startIndex` 是点开的那一张。
    init(entries: [FullscreenEntry], startIndex: Int) {
        _entries = State(initialValue: entries)
        _index = State(initialValue: min(max(startIndex, 0), max(entries.count - 1, 0)))
    }

    /// 当前页的显示图：优先高清，其次预览。
    private var currentImage: UIImage? {
        guard entries.indices.contains(index) else { return nil }
        let entry = entries[index]
        return loaded[entry.id] ?? entry.preview
    }

    private var currentEntry: FullscreenEntry? {
        entries.indices.contains(index) ? entries[index] : nil
    }

    /// 全屏像素：按设备屏幕长边算，1:1 不放大（2048 在 Pro Max 上会被放大 1.4 倍而糊）。
    private var fullMaxPixel: CGFloat {
        let screen = UIScreen.main.bounds
        let longSide = Int(max(screen.width, screen.height) * UIScreen.main.scale)
        return CGFloat(ImageFetchPolicy.fullMaxPixel(screenLongSide: longSide))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                    pageView(for: entry)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: entries.count > 1 ? .automatic : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            .ignoresSafeArea()
            // 放大查看时禁用翻页，否则双指缩放手势会和翻页抢事件。
            .disabled(scale > 1)
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { bottomBar }
        .task(id: index) { await loadFullForCurrentPage() }
    }

    @ViewBuilder
    private func pageView(for entry: FullscreenEntry) -> some View {
        Group {
            if let shown = loaded[entry.id] ?? entry.preview {
                Image(uiImage: shown)
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
            } else if loadingIds.contains(entry.id) {
                ProgressView().tint(.white)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo").font(.largeTitle).foregroundStyle(.white.opacity(0.6))
                    Text(L10n.t("图片加载失败")).font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { circleIcon("xmark") }
                .accessibilityLabel(L10n.t("关闭"))
            Spacer()
            if entries.count > 1 {
                Text("\(index + 1) / \(entries.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
            }
            Spacer()
            if let image = currentImage {
                ShareLink(item: Image(uiImage: image),
                          preview: SharePreview(L10n.t("图片"), image: Image(uiImage: image))) {
                    circleIcon("square.and.arrow.up")
                }
                Button { saveToAlbum() } label: { circleIcon("square.and.arrow.down") }
                    .accessibilityLabel(L10n.t("保存到相册"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let toast {
            Text(toast)
                .font(.footnote)
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.black.opacity(0.65), in: Capsule())
                .padding(.bottom, 24)
        }
    }

    /// 翻到某页才拉该页高清（用户明确要求滑动时才请求，不预取相邻页）。
    private func loadFullForCurrentPage() async {
        guard let entry = currentEntry, let source = entry.source else { return }
        guard loaded[entry.id] == nil else { return }
        loadingIds.insert(entry.id)
        defer { loadingIds.remove(entry.id) }
        let image = await ImagePipeline.shared.image(source: source, tier: .full, maxPixel: fullMaxPixel)
        if let image {
            loaded[entry.id] = image
        } else if entry.preview == nil {
            // 预览也没有、高清也失败：让 pageView 显示失败态。
        } else {
            toast = L10n.t("高清图没拉到，当前是预览图")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                toast = nil
            }
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
        guard let image = currentImage else { return }
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
