import SwiftUI
import UIKit

/// 统一背景纹理内容层：宿主决定尺寸，本层只在宿主尺寸内绘制背景 variant。
struct BackgroundTextureSurface: View {
    let canvasBackground: Color
    let texture: BackgroundTexture
    let textureColor: Color
    let featuredBackground: FeaturedBackground
    let featuredBackgroundOverlay: Color
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
        case .featured:
            FeaturedBackgroundLayer(background: featuredBackground)
                .overlay(featuredBackgroundOverlay)
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

struct FeaturedBackgroundLayer: View {
    let background: FeaturedBackground

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                baseLayer
                atmosphereLayer(size: proxy.size)
                detailLayer(size: proxy.size)
                leadingQuietBand
                fineGrain(opacity: grainOpacity)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
    }

    @ViewBuilder
    private var baseLayer: some View {
        switch background {
        case .mistLake:
            LinearGradient(
                colors: [
                    Color(hex: 0xD9E6EA),
                    Color(hex: 0xAFCAD2),
                    Color(hex: 0xEDF2EC),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .rainWindow:
            LinearGradient(
                colors: [
                    Color(hex: 0xD4DFDA),
                    Color(hex: 0x99B6AD),
                    Color(hex: 0xEEF0E8),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .warmPaper:
            LinearGradient(
                colors: [
                    Color(hex: 0xF1E8D7),
                    Color(hex: 0xDCC6A4),
                    Color(hex: 0xF6EFE2),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .peachDusk:
            LinearGradient(
                colors: [
                    Color(hex: 0x2A2339),
                    Color(hex: 0xB56D74),
                    Color(hex: 0xF2B17C),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .deepAurora:
            LinearGradient(
                colors: [
                    Color(hex: 0x10182A),
                    Color(hex: 0x203953),
                    Color(hex: 0x4B4C8F),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .softBlocks:
            LinearGradient(
                colors: [
                    Color(hex: 0x72CFC8),
                    Color(hex: 0xA7DCCF),
                    Color(hex: 0xE1E7CF),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    @ViewBuilder
    private func atmosphereLayer(size: CGSize) -> some View {
        switch background {
        case .mistLake:
            softOrb(Color.white.opacity(0.50), size: size, scale: 0.86, x: 0.34, y: -0.18)
            softOrb(Color(hex: 0x8DB6C0).opacity(0.22), size: size, scale: 0.62, x: 0.38, y: 0.28)
        case .rainWindow:
            softOrb(Color.white.opacity(0.38), size: size, scale: 0.78, x: 0.32, y: -0.16)
            softOrb(Color(hex: 0x6F9C93).opacity(0.20), size: size, scale: 0.66, x: 0.34, y: 0.30)
        case .warmPaper:
            softOrb(Color(hex: 0xFFF6E2).opacity(0.42), size: size, scale: 0.82, x: 0.32, y: -0.08)
            softOrb(Color(hex: 0xB78B52).opacity(0.12), size: size, scale: 0.72, x: 0.36, y: 0.34)
        case .peachDusk:
            softOrb(Color(hex: 0xFFC28E).opacity(0.62), size: size, scale: 0.78, x: 0.36, y: 0.32)
            softOrb(Color(hex: 0x6F4D82).opacity(0.24), size: size, scale: 0.66, x: 0.26, y: -0.20)
        case .deepAurora:
            softOrb(Color(hex: 0x59B6AE).opacity(0.28), size: size, scale: 0.78, x: 0.36, y: 0.18)
            softOrb(Color(hex: 0xB38EF4).opacity(0.22), size: size, scale: 0.68, x: 0.30, y: -0.20)
        case .softBlocks:
            ZStack {
                RoundedRectangle(cornerRadius: size.width * 0.18, style: .continuous)
                    .fill(Color(hex: 0xF0A45C).opacity(0.42))
                    .frame(width: size.width * 0.48, height: size.height * 0.36)
                    .offset(x: size.width * 0.04, y: -size.height * 0.28)
                RoundedRectangle(cornerRadius: size.width * 0.20, style: .continuous)
                    .fill(Color(hex: 0xC95BC4).opacity(0.34))
                    .frame(width: size.width * 0.58, height: size.height * 0.48)
                    .offset(x: size.width * 0.32, y: size.height * 0.30)
                RoundedRectangle(cornerRadius: size.width * 0.14, style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .frame(width: size.width * 0.42, height: size.height * 0.38)
                    .offset(x: size.width * 0.08, y: size.height * 0.22)
            }
            .blur(radius: 5)
        }
    }

    @ViewBuilder
    private func detailLayer(size: CGSize) -> some View {
        switch background {
        case .mistLake:
            FlowingBands(color: Color.white.opacity(0.20), count: 4, amplitude: 0.018)
        case .rainWindow:
            RainStreakLayer(color: Color.white.opacity(0.20))
        case .warmPaper:
            PaperFiberLayer(color: Color(hex: 0x8B6B44).opacity(0.10))
        case .peachDusk:
            FlowingBands(color: Color(hex: 0xFFE0B9).opacity(0.16), count: 3, amplitude: 0.024)
        case .deepAurora:
            AuroraRibbonLayer()
        case .softBlocks:
            EmptyView()
        }
    }

    private var leadingQuietBand: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.12),
                Color.black.opacity(0.05),
                Color.black.opacity(0.00),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .blendMode(.multiply)
    }

    private var grainOpacity: Double {
        switch background {
        case .warmPaper: return 0.12
        case .deepAurora, .peachDusk: return 0.07
        default: return 0.09
        }
    }

    private func fineGrain(opacity: Double) -> some View {
        Canvas { context, size in
            let spacing: CGFloat = 22
            let radius: CGFloat = 0.55
            var x = spacing * 0.45
            while x <= size.width {
                var y = spacing * 0.45
                while y <= size.height {
                    let rect = CGRect(
                        x: x - radius,
                        y: y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
                    y += spacing
                }
                x += spacing
            }
        }
    }

    private func softOrb(
        _ color: Color,
        size: CGSize,
        scale: CGFloat,
        x: CGFloat,
        y: CGFloat
    ) -> some View {
        RadialGradient(
            colors: [color, color.opacity(0.02)],
            center: .center,
            startRadius: 2,
            endRadius: max(size.width, size.height) * scale
        )
        .offset(x: size.width * x, y: size.height * y)
    }
}

private struct FlowingBands: View {
    let color: Color
    let count: Int
    let amplitude: CGFloat

    var body: some View {
        Canvas { context, size in
            for index in 0..<count {
                var path = Path()
                let progress = CGFloat(index + 1) / CGFloat(count + 1)
                let baseY = size.height * (0.18 + progress * 0.62)
                path.move(to: CGPoint(x: 0, y: baseY))
                path.addCurve(
                    to: CGPoint(x: size.width, y: baseY + size.height * amplitude),
                    control1: CGPoint(x: size.width * 0.28, y: baseY - size.height * amplitude),
                    control2: CGPoint(
                        x: size.width * 0.68, y: baseY + size.height * amplitude * 1.8)
                )
                context.stroke(path, with: .color(color), lineWidth: 1.0)
            }
        }
    }
}

private struct RainStreakLayer: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 22
            var x = size.width * 0.34
            while x <= size.width {
                let top = (x.truncatingRemainder(dividingBy: 58) / 58) * size.height * 0.24
                var path = Path()
                path.move(to: CGPoint(x: x, y: top))
                path.addLine(to: CGPoint(x: x + 8, y: top + size.height * 0.22))
                context.stroke(path, with: .color(color), lineWidth: 0.7)
                x += spacing
            }
        }
    }
}

private struct PaperFiberLayer: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 18
            var y: CGFloat = spacing
            while y <= size.height {
                var path = Path()
                path.move(to: CGPoint(x: size.width * 0.26, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y + 2))
                context.stroke(path, with: .color(color), lineWidth: 0.45)
                y += spacing
            }
        }
    }
}

private struct AuroraRibbonLayer: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: size.width * 0.18, y: size.height * 0.36))
            path.addCurve(
                to: CGPoint(x: size.width * 1.08, y: size.height * 0.20),
                control1: CGPoint(x: size.width * 0.42, y: size.height * 0.14),
                control2: CGPoint(x: size.width * 0.72, y: size.height * 0.44)
            )
            context.stroke(path, with: .color(Color(hex: 0x79D5C7).opacity(0.22)), lineWidth: 18)

            var second = Path()
            second.move(to: CGPoint(x: size.width * 0.22, y: size.height * 0.58))
            second.addCurve(
                to: CGPoint(x: size.width * 1.06, y: size.height * 0.42),
                control1: CGPoint(x: size.width * 0.50, y: size.height * 0.36),
                control2: CGPoint(x: size.width * 0.76, y: size.height * 0.68)
            )
            context.stroke(second, with: .color(Color(hex: 0xBBA1F7).opacity(0.14)), lineWidth: 22)
        }
        .blur(radius: 8)
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
