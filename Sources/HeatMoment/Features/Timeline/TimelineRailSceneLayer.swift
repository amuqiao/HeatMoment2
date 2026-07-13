import SwiftUI

/// 首页时间轴的场景轨道层。
///
/// 轨道属于 `TimelineViewportView` 这个主页场景，不属于任何 `List` row、阅读单元或气泡。
/// `List` 继续承载成熟滚动、定位和系统 `.swipeActions`；本层只消费同一套
/// `TimelineGeometry` 坐标合同绘制稳定背景轴，并关闭命中测试，避免影响点击、横滑和滚动。
struct TimelineRailSceneLayer: View {
    let geometry: TimelineGeometry
    let metrics: TimelineViewportMetrics

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        let railBounds = metrics.railBounds

        Rectangle()
            .fill(theme.timelineRail)
            .frame(width: geometry.railWidth, height: railBounds.height)
            .position(
                x: geometry.railCenterXInViewport,
                y: railBounds.midY
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
