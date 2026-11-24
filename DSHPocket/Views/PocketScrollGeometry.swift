// PocketScrollGeometry

import SwiftUI
import UIKit

/// 滚动几何（偏移 / 距底部距离）的跨版本读取。
///
/// `onScrollGeometryChange` 是 iOS 18 的 API；要支持 iOS 17 必须自己取 UIScrollView 的
/// `contentOffset` / `contentSize` / `bounds`。
///
/// 做法：
/// - iOS 18+：直接用系统 API（零成本、最准）；
/// - iOS 17：在滚动内容里插一个零尺寸的探针视图，顺着 superview 链找到 `UIScrollView`，
///   用 KVO 观察 `contentOffset`（外加 `contentSize`/`bounds` 变化），回调换算后的值。
///
/// 为什么不用 GeometryReader + PreferenceKey：那会在每次滚动时触发布局与 diff，
/// 长会话下是明显的掉帧来源。KVO 直接读 UIKit 的值，不参与 SwiftUI 布局。
enum PocketScrollMetrics {
    /// 从顶部算起的偏移（含 contentInset.top），与系统 `contentOffset.y + contentInsets.top` 一致。
    case topOffset
    /// 距底部的距离，与系统 `contentSize.height - containerSize.height - contentOffset.y` 一致。
    case distanceFromBottom
}

private struct ScrollProbe: UIViewRepresentable {
    let metrics: PocketScrollMetrics
    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.onLayout = { [weak view] in
            guard let scrollView = view?.enclosingScrollView() else { return }
            context.coordinator.attach(to: scrollView, metrics: metrics, onChange: onChange)
        }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.metrics = metrics
        context.coordinator.onChange = onChange
        // 尺寸变化后可能需要重新绑定（例如列表重建）
        if let scrollView = uiView.enclosingScrollView() {
            context.coordinator.attach(to: scrollView, metrics: metrics, onChange: onChange)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class ProbeView: UIView {
        var onLayout: (() -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onLayout?()
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?()
        }
        func enclosingScrollView() -> UIScrollView? {
            var view: UIView? = superview
            while let current = view {
                if let scrollView = current as? UIScrollView { return scrollView }
                view = current.superview
            }
            return nil
        }
    }

    final class Coordinator: NSObject {
        var metrics: PocketScrollMetrics = .topOffset
        var onChange: ((CGFloat) -> Void)?
        private weak var scrollView: UIScrollView?
        private var observations: [NSKeyValueObservation] = []

        func attach(to scrollView: UIScrollView, metrics: PocketScrollMetrics, onChange: @escaping (CGFloat) -> Void) {
            self.metrics = metrics
            self.onChange = onChange
            guard self.scrollView !== scrollView else {
                emit()
                return
            }
            observations.removeAll()
            self.scrollView = scrollView
            let options: NSKeyValueObservingOptions = [.new]
            observations.append(scrollView.observe(\.contentOffset, options: options) { [weak self] _, _ in
                self?.emit()
            })
            observations.append(scrollView.observe(\.contentSize, options: options) { [weak self] _, _ in
                self?.emit()
            })
            emit()
        }

        private func emit() {
            guard let scrollView else { return }
            let value: CGFloat
            switch metrics {
            case .topOffset:
                value = scrollView.contentOffset.y + scrollView.contentInset.top
            case .distanceFromBottom:
                let container = scrollView.bounds.height
                let content = scrollView.contentSize.height + scrollView.adjustedContentInset.bottom
                value = content - container - scrollView.contentOffset.y
            }
            onChange?(value)
        }
    }
}

private struct PocketScrollGeometryModifier: ViewModifier {
    let metrics: PocketScrollMetrics
    let onChange: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            switch metrics {
            case .topOffset:
                content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, new in onChange(new) }
            case .distanceFromBottom:
                content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height - geometry.containerSize.height - geometry.contentOffset.y
                } action: { _, new in onChange(new) }
            }
        } else {
            content
                .background(
                    ScrollProbe(metrics: metrics, onChange: onChange)
                        .frame(width: 0, height: 0)
                )
        }
    }
}

extension View {
    /// 监听滚动几何变化，iOS 17 / 18 行为一致（17 为 KVO 实现）。
    func pocketScrollGeometryChange(_ metrics: PocketScrollMetrics,
                                    onChange: @escaping (CGFloat) -> Void) -> some View {
        modifier(PocketScrollGeometryModifier(metrics: metrics, onChange: onChange))
    }
}
