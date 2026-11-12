// ComposerBar

import SwiftUI

/// 对话页底部输入栏：引用条、草稿图、加号菜单、输入框、发送按钮。
///
/// 为什么单独成文件：这三块（引用/草稿图/输入行）只依赖 model 的草稿状态与两个
/// 「选择器是否展开」的开关，从 740 行的 ConversationView 里拆出来后，
/// 改输入区不必读整套滚动逻辑。
///
/// 注意：`@FocusState` 必须由父视图持有并传入（焦点属于页面，不属于输入栏），
/// 所以这里用 `FocusState<Bool>.Binding`，而不是自己声明。
struct ComposerBar: View {
    @Bindable var model: ConnectionModel
    let session: PocketSession
    /// 选择器展开状态由父视图管理（菜单里只切换状态，真正的 picker 挂在页面上）。
    @Binding var showingPhotoPicker: Bool
    @Binding var showingCamera: Bool
    var focused: FocusState<Bool>.Binding

    /// 加号、输入框、发送三者统一高度。
    static let controlHeight: CGFloat = 36

    private var canSend: Bool {
        !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.draftImages.isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            if let quote = model.pendingQuote {
                quoteBar(quote)
            }
            if !model.draftImages.isEmpty {
                draftImagesRow
            }
            inputRow
        }
        .background(.bar)
    }

    private func quoteBar(_ quote: PendingQuote) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(L10n.t("引用")) \(quote.sender) · #\(quote.sequence)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PocketChrome.brandText)
                Text(quote.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Capsule().fill(Color(red: 0.08, green: 0.48, blue: 0.37)).frame(width: 3)
            }
            Spacer(minLength: 0)
            Button { model.cancelQuote() } label: {
                Image(systemName: "xmark.circle.fill").font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("取消引用"))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var draftImagesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.draftImages) { image in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image.uiImage).resizable().scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Button {
                            model.removeDraftImage(id: image.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.callout)
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .offset(x: 5, y: -5)
                    }
                }
            }.padding(.horizontal).padding(.top, 6)
        }
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Button { showingPhotoPicker = true } label: {
                    Label(L10n.t("相册"), systemImage: "photo")
                }
                Button { showingCamera = true } label: {
                    Label(L10n.t("拍照"), systemImage: "camera")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .pocketSystemGlassCircle(size: Self.controlHeight)
            }
            .accessibilityLabel(L10n.t("添加图片或拍照"))
            TextField(L10n.t("发送消息"), text: $model.draft, axis: .vertical).lineLimit(1...5)
                .focused(focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minHeight: Self.controlHeight)
                .pocketSystemGlassField(cornerRadius: Self.controlHeight / 2)
                .accessibilityIdentifier("composer-field")
            Button {
                focused.wrappedValue = false
                model.sendMessage(in: session)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.subheadline.weight(.bold))
                    .pocketSystemGlassCircle(size: Self.controlHeight)
            }
            .disabled(!canSend)
            .accessibilityLabel(L10n.t("发送消息"))
            .accessibilityIdentifier("send-button")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }
}
