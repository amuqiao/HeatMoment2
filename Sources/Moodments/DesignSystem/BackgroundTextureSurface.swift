import SwiftUI
import UIKit

/// 统一背景纹理内容层：宿主决定尺寸，本层只在宿主尺寸内绘制背景 variant。
struct BackgroundTextureSurface: View {
    let canvasBackground: Color
    let texture: BackgroundTexture
    let textureColor: Color
    let customImageURL: URL?
    let customImageRevision: Int
    let customBackgroundOverlay: Color

    var body: some View {
        canvasBackground
            .overlay {
                GeometryReader { proxy in
                    variantLayer(size: proxy.size)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
    }

    @ViewBuilder
    private func variantLayer(size: CGSize) -> some View {
        switch texture {
        case .grid:
            GridTextureLayer(color: textureColor)
        case .dot:
            DotTextureLayer(color: textureColor)
        case .none:
            EmptyView()
        case .customImage:
            if let customImageURL {
                CustomBackgroundImageLayer(
                    url: customImageURL,
                    revision: customImageRevision,
                    size: size
                )
                .overlay(customBackgroundOverlay)
            }
        }
    }
}

private struct CustomBackgroundImageLayer: View {
    let url: URL
    let revision: Int
    let size: CGSize

    var body: some View {
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .id(revision)
        }
    }
}

struct GridTextureLayer: View {
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

struct DotTextureLayer: View {
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
