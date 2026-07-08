import SwiftUI
import UIKit

/// 首页主场景背景：画布底色 + 用户选择的背景纹理/自定义图片。
///
/// P2a 只把背景作用于首页主场景（含时间轴背后区域与首页顶部热力图上下文），不改变
/// 设置页、编辑器 sheet、气泡卡片或其它系统分组页面的背景语义。
struct HomeSceneBackgroundView: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        ZStack {
            theme.canvasBackground
            backgroundContent
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var backgroundContent: some View {
        switch theme.backgroundTexture {
        case .grid:
            GridTextureLayer(color: theme.homeTextureColor)
        case .dot:
            DotTextureLayer(color: theme.homeTextureColor)
        case .none:
            EmptyView()
        case .customImage:
            customImageLayer
        }
    }

    private var customImageLayer: some View {
        GeometryReader { proxy in
            if let url = theme.customBackgroundImageURL {
                let image = UIImage(
                    contentsOfFile: url.path
                )
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .id(theme.customBackgroundImageRevision)
                        .overlay(theme.customBackgroundOverlay)
                }
            }
        }
    }
}

private struct GridTextureLayer: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let spacing: CGFloat = 24
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(color), lineWidth: 0.6)
        }
    }
}

private struct DotTextureLayer: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 18
            let radius: CGFloat = 1.15
            var x: CGFloat = spacing / 2
            while x <= size.width {
                var y: CGFloat = spacing / 2
                while y <= size.height {
                    let rect = CGRect(
                        x: x - radius,
                        y: y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                    y += spacing
                }
                x += spacing
            }
        }
    }
}
