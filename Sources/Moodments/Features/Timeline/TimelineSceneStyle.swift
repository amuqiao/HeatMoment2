import SwiftUI

/// 首页 timeline 的可换肤样式包。
///
/// 本类型不持有颜色；颜色仍由 `ThemeManager` / `AppThemeTokens` 解析，保证主题颜色是单一真相源。
/// 空间锚点由 `TimelineSceneLayout` / `TimelineGeometry` 持有，视觉样式不反推时间轴坐标。
struct TimelineSceneStyle: Equatable {
    var title: TimelineTitleStyle
    var dateStamp: TimelineDateStampStyle
    var node: TimelineMoodNodeStyle
    var bubble: TimelineBubbleStyle
    var chromeIcon: HomeChromeIconStyle
    var fab: FABStyle

    static let standard = TimelineSceneStyle(
        title: .standard,
        dateStamp: .standard,
        node: .standard,
        bubble: .standard,
        chromeIcon: .standard,
        fab: .standard
    )

    func scaled(with scale: TimelineResponsiveScale) -> Self {
        TimelineSceneStyle(
            title: title.scaled(with: scale),
            dateStamp: dateStamp.scaled(with: scale),
            node: node.scaled(with: scale),
            bubble: bubble.scaled(with: scale),
            chromeIcon: chromeIcon.scaled(with: scale),
            fab: fab.scaled(with: scale)
        )
    }
}

struct TimelineTitleStyle: Equatable {
    var font: Font

    static let standard = TimelineTitleStyle(font: AppTypography.pageTitle)

    func scaled(with _: TimelineResponsiveScale) -> Self { self }

    static func == (lhs: TimelineTitleStyle, rhs: TimelineTitleStyle) -> Bool {
        String(describing: lhs.font) == String(describing: rhs.font)
    }
}

struct TimelineDateStampStyle: Equatable {
    var dayFont: Font
    var monthFont: Font
    var timeFont: Font
    var verticalSpacing: CGFloat
    var timeOnlyTopPadding: CGFloat

    static let standard = TimelineDateStampStyle(
        dayFont: AppTypography.timelineDayNumber,
        monthFont: AppTypography.timelineMonth,
        timeFont: AppTypography.timelineTime,
        verticalSpacing: 2,
        timeOnlyTopPadding: 4
    )

    func scaled(with scale: TimelineResponsiveScale) -> Self {
        TimelineDateStampStyle(
            dayFont: dayFont,
            monthFont: monthFont,
            timeFont: timeFont,
            verticalSpacing: scale.vertical(verticalSpacing),
            timeOnlyTopPadding: scale.vertical(timeOnlyTopPadding)
        )
    }

    static func == (lhs: TimelineDateStampStyle, rhs: TimelineDateStampStyle) -> Bool {
        String(describing: lhs.dayFont) == String(describing: rhs.dayFont)
            && String(describing: lhs.monthFont) == String(describing: rhs.monthFont)
            && String(describing: lhs.timeFont) == String(describing: rhs.timeFont)
            && lhs.verticalSpacing == rhs.verticalSpacing
            && lhs.timeOnlyTopPadding == rhs.timeOnlyTopPadding
    }
}

struct TimelineMoodNodeStyle: Equatable {
    var innerDiameterRatio: CGFloat
    var outerOpacity: Double

    static let standard = TimelineMoodNodeStyle(
        innerDiameterRatio: 0.5,
        outerOpacity: 0.38
    )

    func scaled(with _: TimelineResponsiveScale) -> Self { self }
}

struct TimelineBubbleStyle: Equatable {
    var cornerRadius: CGFloat
    var contentPadding: CGFloat
    var contentSpacing: CGFloat
    var imageGallery: TimelineImageGalleryStyle
    var tagChip: TimelineTagChipStyle
    var tagSpacing: CGFloat

    static let standard = TimelineBubbleStyle(
        cornerRadius: 20,
        contentPadding: 16,
        contentSpacing: 8,
        imageGallery: .standard,
        tagChip: .standard,
        tagSpacing: 6
    )

    func scaled(with scale: TimelineResponsiveScale) -> Self {
        TimelineBubbleStyle(
            cornerRadius: scale.component(cornerRadius),
            contentPadding: scale.component(contentPadding),
            contentSpacing: scale.vertical(contentSpacing),
            imageGallery: imageGallery.scaled(with: scale),
            tagChip: tagChip.scaled(with: scale),
            tagSpacing: scale.horizontal(tagSpacing)
        )
    }
}

struct TimelineImageGalleryStyle: Equatable {
    var thumbnailSize: CGSize
    var thumbnailSpacing: CGFloat
    var thumbnailCornerRadius: CGFloat
    var carouselHeight: CGFloat
    var allowsHitTesting: Bool

    static let standard = TimelineImageGalleryStyle(
        thumbnailSize: CGSize(width: 72, height: 72),
        thumbnailSpacing: 8,
        thumbnailCornerRadius: 12,
        carouselHeight: 132,
        allowsHitTesting: true
    )

    func scaled(with scale: TimelineResponsiveScale) -> Self {
        TimelineImageGalleryStyle(
            thumbnailSize: CGSize(
                width: scale.component(thumbnailSize.width),
                height: scale.component(thumbnailSize.height)
            ),
            thumbnailSpacing: scale.horizontal(thumbnailSpacing),
            thumbnailCornerRadius: scale.component(thumbnailCornerRadius),
            carouselHeight: scale.vertical(carouselHeight),
            allowsHitTesting: allowsHitTesting
        )
    }

    func imageSectionHeight(for mode: ImageDisplayMode) -> CGFloat {
        switch mode {
        case .scroll:
            thumbnailSize.height
        case .carousel:
            carouselHeight
        }
    }
}

struct TimelineTagChipStyle: Equatable {
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat
    var spacing: CGFloat

    static let standard = TimelineTagChipStyle(
        horizontalPadding: 10,
        verticalPadding: 4,
        spacing: 2
    )

    func scaled(with scale: TimelineResponsiveScale) -> Self {
        TimelineTagChipStyle(
            horizontalPadding: scale.horizontal(horizontalPadding),
            verticalPadding: scale.vertical(verticalPadding),
            spacing: scale.horizontal(spacing)
        )
    }
}

struct HomeChromeIconStyle: Equatable {
    var calendarSize: CGSize
    var calendarCornerRadius: CGFloat
    var settingsSize: CGSize
    var strokeWidth: CGFloat

    static let standard = HomeChromeIconStyle(
        calendarSize: CGSize(width: 32, height: 32),
        calendarCornerRadius: 8,
        settingsSize: CGSize(width: 28, height: 28),
        strokeWidth: 1.5
    )

    func scaled(with scale: TimelineResponsiveScale) -> Self {
        HomeChromeIconStyle(
            calendarSize: CGSize(
                width: scale.component(calendarSize.width),
                height: scale.component(calendarSize.height)
            ),
            calendarCornerRadius: scale.component(calendarCornerRadius),
            settingsSize: CGSize(
                width: scale.component(settingsSize.width),
                height: scale.component(settingsSize.height)
            ),
            strokeWidth: scale.component(strokeWidth)
        )
    }
}

struct FABStyle: Equatable {
    var iconSize: CGFloat
    var iconWeight: Font.Weight
    var shadowRadius: CGFloat
    var shadowYOffset: CGFloat

    static let standard = FABStyle(
        iconSize: 24,
        iconWeight: .heavy,
        shadowRadius: 12,
        shadowYOffset: 4
    )

    func scaled(with scale: TimelineResponsiveScale) -> Self {
        FABStyle(
            iconSize: scale.component(iconSize),
            iconWeight: iconWeight,
            shadowRadius: scale.component(shadowRadius),
            shadowYOffset: scale.vertical(shadowYOffset)
        )
    }
}

/// 移动端响应式尺度。基准为 390pt 宽 iPhone，窄屏收紧，宽屏小幅放大。
struct TimelineResponsiveScale: Equatable {
    let viewportWidth: CGFloat
    let horizontalFactor: CGFloat
    let verticalFactor: CGFloat
    let componentFactor: CGFloat

    init(viewportWidth: CGFloat) {
        self.viewportWidth = viewportWidth
        let normalized = viewportWidth / 390
        horizontalFactor = normalized.clamped(to: 0.88...1.12)
        verticalFactor = normalized.clamped(to: 0.92...1.08)
        componentFactor = normalized.clamped(to: 0.90...1.10)
    }

    func horizontal(_ value: CGFloat) -> CGFloat {
        scaled(value, by: horizontalFactor)
    }

    func vertical(_ value: CGFloat) -> CGFloat {
        scaled(value, by: verticalFactor)
    }

    func component(_ value: CGFloat) -> CGFloat {
        scaled(value, by: componentFactor)
    }

    private func scaled(_ value: CGFloat, by factor: CGFloat) -> CGFloat {
        ((value * factor) * 2).rounded(.toNearestOrAwayFromZero) / 2
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
