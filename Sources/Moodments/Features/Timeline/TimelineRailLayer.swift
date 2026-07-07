import SwiftUI

/// 首页时间轴场景里的独立轨道层。
///
/// 轨道不放进 `TimelineRowView` 的内容层，也不挂在任何 `List` 行上。它作为
/// `TimelineListView` 的结构层存在：x 坐标由 `List` 内的真实布局 probe 测量，y 坐标根据
/// 滚动相位计算。下拉时轨道 top 固定；上滑时轨道随时间轴场景向上移动，底部持续延伸到屏幕外。
struct TimelineRailLayer: View {
    let geometry: TimelineGeometry
    let railX: CGFloat
    let initialTopY: CGFloat
    let scrollOffsetY: CGFloat

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        GeometryReader { proxy in
            let upwardScroll = max(scrollOffsetY, 0)
            let topY = initialTopY - upwardScroll
            let height = max(
                0,
                proxy.size.height - topY + geometry.railBottomOvershoot + upwardScroll
            )

            Rectangle()
                .fill(theme.timelineRail)
                .frame(width: 1, height: height)
                .position(
                    x: railX,
                    y: topY + height / 2
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
