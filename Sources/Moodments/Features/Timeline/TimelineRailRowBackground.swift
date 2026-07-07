import SwiftUI

/// `List` 行背景中的时间轴轨道。
///
/// SwiftUI `List` 由 UIKit 承载时，外部 sibling overlay 可能被 cell 层遮挡；轨道放在
/// `listRowBackground` 中，仍不属于可横向滑动的阅读单元内容，同时能在 lead-in、记录行
/// 和底部 overshoot 中稳定连成一根视觉轴。
struct TimelineRailRowBackground: View {
    let geometry: TimelineGeometry
    var highlightColor: Color?

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let highlightColor {
                    highlightColor
                } else {
                    Color.clear
                }

                Rectangle()
                    .fill(theme.timelineRail)
                    .frame(width: 1, height: proxy.size.height)
                    .position(
                        x: geometry.railCenterXInViewport,
                        y: proxy.size.height / 2
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
