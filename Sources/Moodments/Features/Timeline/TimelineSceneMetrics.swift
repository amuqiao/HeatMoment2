import SwiftUI

/// 首页时间轴场景的响应式布局与可换肤样式入口。
///
/// - `layout` 只表达稳定坐标和呼吸节奏。
/// - `style` 只表达字体、形状、图标和效果，不反推时间轴锚点。
/// 后续接入皮肤管理时，应优先替换 `TimelineSceneStyle`，不要改阅读单元坐标。
struct TimelineSceneMetrics: Equatable {
    let layout: TimelineSceneLayout
    let style: TimelineSceneStyle

    static func responsive(
        for viewportWidth: CGFloat,
        baseStyle: TimelineSceneStyle = .standard
    ) -> Self {
        let scale = TimelineResponsiveScale(viewportWidth: viewportWidth)
        let style = baseStyle.scaled(with: scale)
        return TimelineSceneMetrics(
            layout: TimelineSceneLayout.responsive(with: scale),
            style: style
        )
    }
}

/// 首页 timeline 的三段式布局骨架：固定 chrome、首屏 rhythm、阅读单元几何。
struct TimelineSceneLayout: Equatable {
    let home: TimelineHomeLayout
    let viewport: TimelineViewportLayout
    let geometry: TimelineGeometry

    static func responsive(with scale: TimelineResponsiveScale) -> Self {
        let baseGeometry = TimelineGeometry.standard
        let baseHome = TimelineHomeLayout.standard
        let baseViewport = TimelineViewportLayout.standard
        let nodeDiameter = scale.component(baseGeometry.nodeDiameter)
        let nodeColumnWidth = max(
            scale.horizontal(baseGeometry.nodeColumnWidth),
            nodeDiameter + scale.horizontal(2)
        )
        let geometry = TimelineGeometry(
            listHorizontalInset: scale.horizontal(baseGeometry.listHorizontalInset),
            dateColumnWidth: scale.horizontal(baseGeometry.dateColumnWidth),
            interColumnSpacing: scale.horizontal(baseGeometry.interColumnSpacing),
            nodeColumnWidth: nodeColumnWidth,
            nodeDiameter: nodeDiameter,
            nodeCenterY: scale.vertical(baseGeometry.nodeCenterY),
            rowGapHeight: scale.vertical(baseGeometry.rowGapHeight),
            firstNodeCenterYOffsetFromRailTop: scale.vertical(
                baseGeometry.firstNodeCenterYOffsetFromRailTop
            ),
            railWidth: scale.component(baseGeometry.railWidth),
            bubbleTailSize: CGSize(
                width: scale.horizontal(baseGeometry.bubbleTailSize.width),
                height: scale.vertical(baseGeometry.bubbleTailSize.height)
            ),
            bubbleTailHorizontalOffset: (baseGeometry.bubbleTailHorizontalOffset < 0 ? -1 : 1)
                * scale.horizontal(abs(baseGeometry.bubbleTailHorizontalOffset))
        )

        return TimelineSceneLayout(
            home: TimelineHomeLayout(
                topChromeHorizontalPadding: scale.horizontal(baseHome.topChromeHorizontalPadding),
                topChromeVerticalPadding: scale.vertical(baseHome.topChromeVerticalPadding),
                fabDiameter: scale.component(baseHome.fabDiameter),
                fabBottomPadding: scale.vertical(baseHome.fabBottomPadding),
                fabSafetyGap: scale.vertical(baseHome.fabSafetyGap)
            ),
            viewport: TimelineViewportLayout(
                expandedTitleSlotBottomY: scale.vertical(baseViewport.expandedTitleSlotBottomY),
                expandedTitleTopPadding: baseViewport.expandedTitleTopPadding,
                titleToRailTopSpacing: scale.vertical(baseViewport.titleToRailTopSpacing),
                railBottomOvershoot: scale.vertical(baseViewport.railBottomOvershoot)
            ),
            geometry: geometry
        )
    }
}
