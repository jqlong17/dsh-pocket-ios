// ComposerTextView

import SwiftUI
import UIKit

/// 输入框的 UIKit 版：为了拿到「回车键」和「输入法组字」的真实状态。
///
/// 为什么不用 SwiftUI `TextField`（2026-11-26 iPad 实测）：
/// `.onKeyPress` 在 TextField 获得焦点时收不到硬件回车（键先被文本控件吃掉），
/// 于是「回车发送」永远不生效。只有在 `UITextViewDelegate` 里拦 Return 才可靠；
/// 同时可以用 `markedTextRange` 判断输入法是否正在组字——组字中的回车必须让给输入法，
/// 否则英文候选会被吞掉（这就是「中文输入法里英文输不进去」的原因）。
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let isFocused: Bool
    let onFocusChange: (Bool) -> Void
    let onSend: () -> Void

    func makeUIView(context: Context) -> ContainerView {
        let view = ContainerView()
        view.textView.delegate = context.coordinator
        view.textView.font = .preferredFont(forTextStyle: .body)
        view.textView.adjustsFontForContentSizeCategory = true
        view.textView.backgroundColor = .clear
        view.textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        view.textView.textContainer.lineFragmentPadding = 0
        view.textView.isScrollEnabled = false
        view.textView.returnKeyType = .send
        view.textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.placeholderLabel.text = placeholder
        view.placeholderLabel.font = .preferredFont(forTextStyle: .body)
        view.placeholderLabel.adjustsFontForContentSizeCategory = true
        view.placeholderLabel.textColor = .placeholderText
        view.textView.text = text
        view.updatePlaceholder()
        return view
    }

    func updateUIView(_ view: ContainerView, context: Context) {
        context.coordinator.parent = self
        if view.textView.text != text { view.textView.text = text }
        view.placeholderLabel.text = placeholder
        view.updatePlaceholder()

        if isFocused, !view.textView.isFirstResponder {
            view.textView.becomeFirstResponder()
        } else if !isFocused, view.textView.isFirstResponder {
            view.textView.resignFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ContainerView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let fitting = uiView.textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: min(max(fitting, minHeight), maxHeight))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class ContainerView: UIView {
        let textView = UITextView()
        let placeholderLabel = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)
            textView.translatesAutoresizingMaskIntoConstraints = false
            placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
            placeholderLabel.numberOfLines = 1
            addSubview(textView)
            addSubview(placeholderLabel)
            NSLayoutConstraint.activate([
                textView.leadingAnchor.constraint(equalTo: leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: trailingAnchor),
                textView.topAnchor.constraint(equalTo: topAnchor),
                textView.bottomAnchor.constraint(equalTo: bottomAnchor),
                placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: textView.textContainerInset.left + 4),
                placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: textView.textContainerInset.top),
                placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

        func updatePlaceholder() {
            placeholderLabel.isHidden = !textView.text.isEmpty
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerTextView

        init(parent: ComposerTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            (textView.superview as? ContainerView)?.updatePlaceholder()
        }

        func textViewDidBeginEditing(_ textView: UITextView) { parent.onFocusChange(true) }
        func textViewDidEndEditing(_ textView: UITextView) { parent.onFocusChange(false) }

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard text == "\n" else { return true }
            // 输入法正在组字：把回车让给它上屏候选（中英混输时必须这样）
            if let marked = textView.markedTextRange, !(textView.text(in: marked) ?? "").isEmpty {
                return true
            }
            guard !parent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !parent.text.isEmpty else { return false }
            parent.onSend()
            return false
        }
    }
}
