import SwiftUI
import UIKit

/// 场景轨道在 viewport 坐标系中的实测边界。
///
/// 轨道顶点和底端必须由真实布局测量得出，不能写成固定 magic number；否则顶部 chrome、
/// 热力图、上下文标记或记录数量变化时，轨道会重新错位或留下无归属残线。
struct TimelineRailSceneBounds: Equatable {
    let topY: CGFloat
    let bottomY: CGFloat

    var height: CGFloat {
        max(0, bottomY - topY)
    }

    var midY: CGFloat {
        topY + height / 2
    }
}

struct TimelineRailBoundsReporter: View {
    let coordinateSpaceName: String
    let edge: TimelineRailMeasuredEdge

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(coordinateSpaceName))
            Color.clear.preference(
                key: TimelineRailBoundsPreferenceKey.self,
                value: TimelineRailBoundsPreference(edge: edge, frame: frame)
            )
        }
    }
}

enum TimelineRailMeasuredEdge {
    case top
    case bottom
}

struct TimelineRailBoundsPreference: Equatable {
    var topY: CGFloat?
    var bottomY: CGFloat?

    init(topY: CGFloat? = nil, bottomY: CGFloat? = nil) {
        self.topY = topY
        self.bottomY = bottomY
    }

    init(edge: TimelineRailMeasuredEdge, frame: CGRect) {
        switch edge {
        case .top:
            self.init(topY: frame.minY)
        case .bottom:
            self.init(bottomY: frame.maxY)
        }
    }

    var bounds: TimelineRailSceneBounds? {
        guard let topY, let bottomY, bottomY > topY else { return nil }
        return TimelineRailSceneBounds(topY: topY, bottomY: bottomY)
    }
}

struct TimelineRailBoundsPreferenceKey: PreferenceKey {
    static let defaultValue = TimelineRailBoundsPreference()

    static func reduce(
        value: inout TimelineRailBoundsPreference,
        nextValue: () -> TimelineRailBoundsPreference
    ) {
        let next = nextValue()
        value.topY = next.topY ?? value.topY
        value.bottomY = next.bottomY ?? value.bottomY
    }
}

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
