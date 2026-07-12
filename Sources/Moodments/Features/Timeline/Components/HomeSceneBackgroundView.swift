import SwiftUI

/// 首页主场景背景：画布底色 + 用户选择的背景纹理/自定义图片。
///
/// 只由首页 scene host 挂载；顶部 chrome、首页热力图上下文、设置页、编辑器 sheet、气泡卡片
/// 或其它 surface 不应再次实例化本背景，否则自定义图片会按局部容器重新裁切。
struct HomeSceneBackgroundView: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        BackgroundTextureSurface(
            canvasBackground: theme.canvasBackground,
            texture: theme.backgroundTexture,
            textureColor: theme.homeTextureColor,
            customImageURL: theme.customBackgroundImageURL,
            customImageRevision: theme.customBackgroundImageRevision,
            customBackgroundOverlay: theme.customBackgroundOverlay
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
