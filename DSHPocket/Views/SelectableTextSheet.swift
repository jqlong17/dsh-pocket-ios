// SelectableTextSheet

import SwiftUI
import UIKit

/// 纯文本选择面板：长按选不中时的可靠出口。
///
/// 为什么需要（2026-11-26 iPad 实测）：气泡里的 Markdown 用 SwiftUI `Text` 渲染，
/// 长按只弹系统菜单、没有任何选中高亮（textSelection 在这层不生效）。
/// 与其把渲染换成 UITextView（会丢跨块选择与表格/代码块样式），
/// 不如给一条明确出口：把该条消息原文塞进原生 UITextView，选择与复制交给系统。
struct SelectableTextSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableTextView(text: text)
                .padding(12)
                .navigationTitle(L10n.t("选择文本"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.t("完成")) { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            UIPasteboard.general.string = text
                        } label: {
                            Label(L10n.t("复制全部"), systemImage: "doc.on.doc")
                        }
                    }
                }
        }
    }
}

private struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.alwaysBounceVertical = true
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.text = text
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
    }
}
