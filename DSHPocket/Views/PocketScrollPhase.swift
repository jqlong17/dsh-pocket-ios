// PocketScrollPhase

import SwiftUI

/// 「用户正在滚动」的跨版本信号。
///
/// `onScrollPhaseChange`（iOS 18）是系统级信号，最准；但我们要支持 iOS 17，
/// 那上面没有这个 API。这里做一层封装：
///
/// - iOS 18+：直接用系统的滚动相位；
/// - iOS 17：用 `DragGesture(minimumDistance: 0)` 近似 ——
///   **0 距离**是关键，6pt 门槛的拖拽会漏掉 3-5pt 的轻扫（那正是
///   「滑一下就被弹回」漏掉的一段，历史上踩过）。
enum PocketScrollPhase {
    /// 手指在列表上（拖拽/减速中）。
    case interacting
    /// 静止。
    case idle
    /// 其它系统相位（tracking/decelerating 等），调用方多数不关心。
    case other
}

private struct PocketScrollPhaseModifier: ViewModifier {
    let onChange: (PocketScrollPhase) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                switch phase {
                case .interacting:
                    onChange(.interacting)
                case .idle:
                    onChange(.idle)
                default:
                    onChange(.other)
                }
            }
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onChange(.interacting) }
                    .onEnded { _ in onChange(.idle) }
            )
        }
    }
}

extension View {
    /// 监听「用户是否正在滚动」，iOS 17 与 18 行为一致（17 为近似实现）。
    func pocketScrollPhaseChange(_ onChange: @escaping (PocketScrollPhase) -> Void) -> some View {
        modifier(PocketScrollPhaseModifier(onChange: onChange))
    }
}
