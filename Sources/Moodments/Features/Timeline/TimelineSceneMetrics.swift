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
        baseStyle: TimelineSceneStyle = .standard,
        layoutTokens: TimelineLayoutTokens = .standard
    ) -> Self {
        let scale = TimelineResponsiveScale(viewportWidth: viewportWidth)
        let style = baseStyle.scaled(with: scale)
        return TimelineSceneMetrics(
            layout: TimelineLayoutResolver.resolve(tokens: layoutTokens, scale: scale),
            style: style
        )
    }
}

/// 首页 timeline 的三段式布局骨架：固定 chrome、首屏 rhythm、阅读单元几何。
struct TimelineSceneLayout: Equatable {
    let home: TimelineHomeLayout
    let viewport: TimelineViewportLayout
    let geometry: TimelineGeometry
}
