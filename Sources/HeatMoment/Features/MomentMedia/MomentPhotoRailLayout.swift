import SwiftUI

/// Moment 编辑/预览照片轨道的稳定尺寸规则。
///
/// 外层页面由任务内容列负责宽度；本规则只约束横向照片轨道内部：
/// 所有照片同高，宽度按图片比例决定并经过上下限夹取，避免极端图片破坏阅读节奏。
enum MomentPhotoRailLayout {
    static let itemHeight: CGFloat = 168
    static let itemSpacing: CGFloat = 12
    static let itemCornerRadius: CGFloat = 14
    static let minimumAspectRatio: CGFloat = 0.54
    static let maximumAspectRatio: CGFloat = 1.60
    static let fallbackAspectRatio: CGFloat = 0.72
    static let deleteBadgeDiameter: CGFloat = 24
    static let deleteBadgeOffset: CGFloat = 10
    static let deleteBadgeBorderWidth: CGFloat = 1

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
