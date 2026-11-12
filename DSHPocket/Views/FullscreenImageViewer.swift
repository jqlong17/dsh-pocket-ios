// FullscreenImageViewer

import SwiftUI
import DSHKit
import UIKit
import Photos
import ImageIO

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
            // 不 disabled(scale > 1)：那会把 TabView 的分页手势一起禁掉，
            // 一旦缩放状态没复位就再也翻不动。放大与翻页靠 simultaneousGesture 共存。
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { bottomBar }
        // 进入时预加载当前页与左右相邻；滑动到新页时补加载。
        // 页面容器已固定尺寸（见 pageView），所以加载完成不会改变布局；
        // 写入 loaded 时再关掉动画，避免任何残留的隐式动画干扰分页。
        .task(id: index) { await loadFullForCurrentPage() }
    }

    private func pageView(for entry: FullscreenEntry) -> some View {
        // 固定容器：图片从 640（预览）换成 2868（高清）时，显示区域始终是整屏。
        // 否则每次替换都会改变页面尺寸 → TabView 重新布局 → 首次滑动停在两页中间（实测）。
        GeometryReader { geo in
            ZStack {
                if let shown = loaded[entry.id] ?? entry.preview {
                    Image(uiImage: shown)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                        // 不挂 MagnificationGesture：连续手势会和分页拖拽在识别层竞争。
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
            .frame(width: geo.size.width, height: geo.size.height)
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

    /// 加载当前页 + 左右相邻各一张的高清。
    ///
    /// 为什么要预加载相邻页：只加载当前页时，滑过去要等一次网络往返，
    /// 用户看到的是「先糊后清」；预加载让滑动当下就是高清。
    /// 只预取相邻一张（不是全部），三张的流量与内存是可接受的。
    private func loadFullForCurrentPage() async {
        let targets = [index - 1, index, index + 1].filter { entries.indices.contains($0) }
        await withTaskGroup(of: Void.self) { group in
            for target in targets {
                group.addTask { await loadFull(at: target, showFailureToast: target == index) }
            }
        }
    }

    private func loadFull(at target: Int, showFailureToast: Bool) async {
        guard entries.indices.contains(target) else { return }
        let entry = entries[target]
        guard let source = entry.source else { return }
        if loaded[entry.id] != nil { return }
        await MainActor.run { _ = loadingIds.insert(entry.id) }
        let image = await ImagePipeline.shared.image(source: source, tier: .full, maxPixel: fullMaxPixel)
        await MainActor.run {
            loadingIds.remove(entry.id)
            if let image {
                // 关闭动画：图片替换本身不需要动效，带隐式动画会让分页手势的动画被重置。
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { loaded[entry.id] = image }
            } else if showFailureToast, entry.preview != nil {
                toast = L10n.t("高清图没拉到，当前是预览图")
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    toast = nil
                }
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
