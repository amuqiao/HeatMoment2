import CoreGraphics

/// 首页场景级 resolved 垂直布局。
///
/// 它是 `TimelineLayoutResolver` 的输出，不是人工调参入口；主页固定 chrome、FAB 和时间轴
/// 滚动尾部避让的设计意图由 `TimelineLayoutTokens` 持有。
struct TimelineHomeLayout: Equatable {
    static let standard = TimelineLayoutResolver.resolve(
        scale: TimelineResponsiveScale(viewportWidth: 390)
    ).home

    let topChromeHorizontalPadding: CGFloat
    let topChromeVerticalPadding: CGFloat
    let fabDiameter: CGFloat
    let fabBottomPadding: CGFloat
    let fabSafetyGap: CGFloat
    let fabVisualProtectionInset: CGFloat

    init(
        topChromeHorizontalPadding: CGFloat,
        topChromeVerticalPadding: CGFloat,
        fabDiameter: CGFloat,
        fabBottomPadding: CGFloat,
        fabSafetyGap: CGFloat,
        fabVisualProtectionInset: CGFloat
    ) {
        self.topChromeHorizontalPadding = topChromeHorizontalPadding
        self.topChromeVerticalPadding = topChromeVerticalPadding
        self.fabDiameter = fabDiameter
        self.fabBottomPadding = fabBottomPadding
        self.fabSafetyGap = fabSafetyGap
        self.fabVisualProtectionInset = fabVisualProtectionInset
    }

    var bottomActionClearance: CGFloat {
        fabDiameter + fabBottomPadding + fabSafetyGap + fabVisualProtectionInset
    }
}
