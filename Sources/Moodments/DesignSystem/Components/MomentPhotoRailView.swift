import SwiftUI

/// Moment 详情/编辑照片轨道的稳定尺寸规则。
///
/// 外层页面仍由 `TaskPageScrollView` / `TaskResponsiveContent` 负责内容列宽度；本规则只约束
/// 横向照片轨道内部：所有照片同高，宽度按图片比例决定，但经过上下限夹取，避免超窄/超宽
/// 图片破坏编辑页和预览页的稳定阅读节奏。
enum MomentPhotoRailLayout {
    static let itemHeight: CGFloat = 168
    static let itemSpacing: CGFloat = 12
    static let itemCornerRadius: CGFloat = 14
    static let minimumAspectRatio: CGFloat = 0.54
    static let maximumAspectRatio: CGFloat = 1.60
    static let fallbackAspectRatio: CGFloat = 0.72
    static let deleteBadgeDiameter: CGFloat = 28

    static var fallbackItemSize: CGSize {
        CGSize(width: itemHeight * fallbackAspectRatio, height: itemHeight)
    }

    static func itemSize(for imageSize: CGSize) -> CGSize {
        CGSize(width: itemWidth(for: imageSize), height: itemHeight)
    }

    static func itemWidth(for imageSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return fallbackItemSize.width
        }
        let aspectRatio = imageSize.width / imageSize.height
        let clampedAspectRatio = min(max(aspectRatio, minimumAspectRatio), maximumAspectRatio)
        return itemHeight * clampedAspectRatio
    }
}
