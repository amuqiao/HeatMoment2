import CoreGraphics

/// 首页场景级垂直布局。
///
/// 它只描述主页固定 chrome、FAB 和时间轴滚动尾部避让，不进入时间轴阅读单元内部坐标；
/// 阅读单元仍由 `TimelineGeometry` 管。
struct TimelineHomeLayout {
    static let standard = TimelineHomeLayout()

    let topChromeHorizontalPadding: CGFloat
    let topChromeVerticalPadding: CGFloat
    let fabDiameter: CGFloat
    let fabBottomPadding: CGFloat
    let fabSafetyGap: CGFloat

    init(
        topChromeHorizontalPadding: CGFloat = 20,
        topChromeVerticalPadding: CGFloat = 8,
        fabDiameter: CGFloat = FABButtonMetrics.diameter,
        fabBottomPadding: CGFloat = 24,
        fabSafetyGap: CGFloat = 8
    ) {
        self.topChromeHorizontalPadding = topChromeHorizontalPadding
        self.topChromeVerticalPadding = topChromeVerticalPadding
        self.fabDiameter = fabDiameter
        self.fabBottomPadding = fabBottomPadding
        self.fabSafetyGap = fabSafetyGap
    }

    var bottomActionClearance: CGFloat {
        fabDiameter + fabBottomPadding + fabSafetyGap
    }
}
