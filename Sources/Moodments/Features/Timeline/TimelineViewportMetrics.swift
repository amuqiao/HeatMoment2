import SwiftUI

/// 首页时间轴 viewport 的 resolved 场景布局合同。
///
/// 这里描述的是首页首屏场景的稳定槽位，不测量 `List` row 或 `Text` 像素高度。调整顶部
/// chrome、展开标题和轨道呼吸空间时，修改 `TimelineLayoutTokens`，不要直接改本类型。
struct TimelineViewportLayout: Equatable {
    static let standard = TimelineLayoutResolver.resolve(
        scale: TimelineResponsiveScale(viewportWidth: 390)
    ).viewport

    let expandedTitleSlotBottomY: CGFloat
    let expandedTitleTopPadding: CGFloat
    let titleToRailTopSpacing: CGFloat
    let railBottomOvershoot: CGFloat

    init(
        expandedTitleSlotBottomY: CGFloat,
        expandedTitleTopPadding: CGFloat,
        titleToRailTopSpacing: CGFloat,
        railBottomOvershoot: CGFloat
    ) {
        self.expandedTitleSlotBottomY = expandedTitleSlotBottomY
        self.expandedTitleTopPadding = expandedTitleTopPadding
        self.titleToRailTopSpacing = titleToRailTopSpacing
        self.railBottomOvershoot = railBottomOvershoot
    }

    var restingRailTopY: CGFloat {
        expandedTitleSlotBottomY + titleToRailTopSpacing
    }
}

/// 首页时间轴 viewport 的运行时坐标。
///
/// `TimelineGeometry` 只描述阅读单元内部的相对关系；本类型负责把当前 viewport 尺寸、
/// scroll offset 和首页首屏场景合同合成为场景轨道的绝对坐标。
struct TimelineViewportMetrics: Equatable {
    let viewportSize: CGSize
    let scrollOffsetY: CGFloat
    let sceneLayout: TimelineSceneLayout

    init(
        viewportSize: CGSize,
        scrollOffsetY: CGFloat,
        sceneLayout: TimelineSceneLayout
    ) {
        self.viewportSize = viewportSize
        self.scrollOffsetY = scrollOffsetY
        self.sceneLayout = sceneLayout
    }

    /// 下拉时轨道不被拉低；上滑时轨道随时间轴内容向上进入顶部 chrome。
    var railTopY: CGFloat {
        sceneLayout.viewport.restingRailTopY - max(0, scrollOffsetY)
    }

    var railBottomY: CGFloat {
        max(railTopY, viewportSize.height + sceneLayout.viewport.railBottomOvershoot)
    }

    var railBounds: TimelineRailSceneBounds {
        TimelineRailSceneBounds(topY: railTopY, bottomY: railBottomY)
    }

    var restingFirstNodeCenterY: CGFloat {
        sceneLayout.viewport.restingRailTopY
            + sceneLayout.geometry.firstNodeCenterYOffsetFromRailTop
    }
}
