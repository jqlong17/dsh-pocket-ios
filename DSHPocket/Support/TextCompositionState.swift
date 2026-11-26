// TextCompositionState

import UIKit

/// 当前输入框是否正在「组字」（中文/日文输入法把拼音挂在 unmarked 状态里）。
///
/// 为什么需要（2026-11-26 iPad 实测）：外接键盘按回车时，
/// 中文输入法正把英文候选挂在 markedTextRange 里，回车应该**先上屏候选**；
/// 如果此时由我们的回车处理器直接发送，候选会被吞掉，表现为「英文输不进去」。
enum TextCompositionState {
    static var hasMarkedText: Bool {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return false }
        for window in scene.windows {
            guard let responder = firstResponder(in: window),
                  let input = responder as? UITextInput,
                  let marked = input.markedTextRange else { continue }
            if !(input.text(in: marked) ?? "").isEmpty { return true }
        }
        return false
    }

    private static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for subview in view.subviews {
            if let found = firstResponder(in: subview) { return found }
        }
        return nil
    }
}
