import SwiftUI

struct FeaturedBackgroundView: View {
    @Environment(ThemeManager.self) private var theme

    private let columns = [
        GridItem(.adaptive(minimum: 138, maximum: 180), spacing: 14)
    ]

    var body: some View {
        let isFeaturedActive = theme.backgroundTexture == .featured
        TaskPageScrollView(spacing: 20, accessibilityIdentifier: "featuredBackgroundScrollView") {
            TaskSurfaceSection(
                title: isFeaturedActive ? "当前选择" : "精选预览",
                accessibilityIdentifier: "featuredBackgroundPreviewSection"
            ) {
                FeaturedBackgroundArtwork(background: theme.featuredBackground)
                    .frame(height: 226)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(theme.separator.opacity(0.62), lineWidth: 1)
                    )
                    .accessibilityIdentifier("featuredBackgroundCurrentPreview")
            }

            TaskSurfaceSection(
                title: "精选背景", accessibilityIdentifier: "featuredBackgroundGridSection"
            ) {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(FeaturedBackground.allCases) { background in
                        FeaturedBackgroundOptionCard(
                            background: background,
                            isSelected: isFeaturedActive && theme.featuredBackground == background
                        ) {
                            theme.setFeaturedBackground(background)
                        }
                    }
                }
            }
        }
        .appSheetDetailNavigationChrome("精选背景")
        .themedTaskContainer(theme)
    }
}

private struct FeaturedBackgroundOptionCard: View {
    @Environment(ThemeManager.self) private var theme

    let background: FeaturedBackground
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                FeaturedBackgroundArtwork(background: background)
                    .frame(height: 154)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(selectionBorder)

                Text(background.displayName)
                    .font(AppTypography.caption.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("featuredBackgroundOption-\(background.rawValue)")
        .accessibilityLabel(Text("精选背景：\(background.displayName)"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var selectionBorder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(
                isSelected ? theme.accent : theme.separator.opacity(0.62),
                lineWidth: isSelected ? 2 : 1
            )
    }
}

private struct FeaturedBackgroundArtwork: View {
    @Environment(ThemeManager.self) private var theme

    let background: FeaturedBackground

    var body: some View {
        GeometryReader { proxy in
            BackgroundTextureSurface(
                canvasBackground: theme.canvasBackground,
                texture: .featured,
                textureColor: theme.homeTextureColor,
                featuredBackground: background,
                featuredBackgroundOverlay: theme.featuredBackgroundOverlay,
                customImageURL: nil,
                customImageRevision: 0,
                customBackgroundOverlay: theme.customBackgroundOverlay
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
    }
}

#Preview {
    NavigationStack {
        FeaturedBackgroundView()
    }
    .environment(ThemeManager())
}
