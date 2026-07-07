import SwiftUI
import UIKit

/// 监听时间轴滚动位置，驱动标题两态折叠。
///
/// 折叠判定：内容自顶部上滑超过 `|threshold|` 点即判定为收起态（`threshold` 为负，见调用处）。
struct TimelineScrollObserver: ViewModifier {
    let threshold: CGFloat
    @Binding var isCollapsed: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                // 顶部时 contentOffset.y == -contentInsets.top，二者相加为 0；上滑后为正。
                let offsetY = geometry.contentOffset.y + geometry.contentInsets.top
                return offsetY > -threshold
            } action: { _, state in
                isCollapsed = state
            }
        } else {
            content.background(
                TimelineScrollOffsetReader { offsetY in
                    isCollapsed = offsetY > -threshold
                }
                .frame(width: 0, height: 0)
            )
        }
    }
}

/// iOS 17 没有 `onScrollGeometryChange`，这里用一个零尺寸 UIView 挂到 `List` 自身，
/// 直接读取承载它的 `UIScrollView` 偏移；它只提供标题折叠相位，不反推轨道或节点位置。
private struct TimelineScrollOffsetReader: UIViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> OffsetReaderView {
        let view = OffsetReaderView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: OffsetReaderView, context: Context) {
        uiView.onChange = onChange
        uiView.attachIfNeeded()
    }

    final class OffsetReaderView: UIView {
        var onChange: (CGFloat) -> Void = { _ in }

        private weak var observedScrollView: UIScrollView?
        private var contentOffsetObservation: NSKeyValueObservation?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachIfNeeded()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            emitCurrentOffset()
        }

        func attachIfNeeded() {
            DispatchQueue.main.async { [weak self] in
                self?.attachToEnclosingScrollView()
            }
        }

        private func attachToEnclosingScrollView() {
            guard let scrollView = enclosingScrollView(), scrollView !== observedScrollView else {
                emitCurrentOffset()
                return
            }

            observedScrollView = scrollView
            contentOffsetObservation = scrollView.observe(
                \.contentOffset,
                options: [.initial, .new]
            ) { [weak self, weak scrollView] _, _ in
                DispatchQueue.main.async {
                    guard let scrollView else { return }
                    self?.emit(scrollView)
                }
            }
        }

        private func emitCurrentOffset() {
            guard let observedScrollView else { return }
            emit(observedScrollView)
        }

        private func emit(_ scrollView: UIScrollView) {
            onChange(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
        }

        private func enclosingScrollView() -> UIScrollView? {
            var view = superview
            while let candidate = view {
                if let scrollView = candidate as? UIScrollView {
                    return scrollView
                }
                view = candidate.superview
            }
            return nil
        }
    }
}
