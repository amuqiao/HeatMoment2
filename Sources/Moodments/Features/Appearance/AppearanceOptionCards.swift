import SwiftUI

private enum AppearancePreviewMetrics {
    static let cornerRadius: CGFloat = 13
    static let texturePreviewHeight: CGFloat = 106
    static let textureOptionHeight: CGFloat = 132
    static let modeOverviewSize = CGSize(width: 88, height: 132)
}

private extension View {
    @ViewBuilder
    func appearancePreviewMeasurementIdentifier(_ identifier: String) -> some View {
        #if DEBUG
            let shouldExposeIdentifier = UITestSupport.wantsTaskSurfaceMeasurementIdentifiers
        #else
            let shouldExposeIdentifier = false
        #endif

        if shouldExposeIdentifier {
            overlay {
                Color.clear
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier(identifier)
                    .allowsHitTesting(false)
            }
        } else {
            self
        }
    }
}

struct AppearanceInlineNotice: View {
    @Environment(ThemeManager.self) private var theme

    let text: String
    let identifier: String
    let color: Color

    var body: some View {
        Text(text)
            .font(AppTypography.caption)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.sheetPanelBackground)
            )
            .accessibilityIdentifier(identifier)
    }
}

struct AppearanceModeOptionCard: View {
    @Environment(ThemeManager.self) private var theme

    let mode: ThemeMode
    let title: String
    let texture: BackgroundTexture
    let customImageURL: URL?
    let customImageRevision: Int
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                AppearanceThemeOverviewPreview(
                    mode: mode,
                    accentColor: theme.accentColor,
                    texture: texture,
                    customImageURL: customImageURL,
                    customImageRevision: customImageRevision
                )
                .frame(
                    width: AppearancePreviewMetrics.modeOverviewSize.width,
                    height: AppearancePreviewMetrics.modeOverviewSize.height
                )
                .appearancePreviewMeasurementIdentifier("appearanceModePreview-\(mode.rawValue)")

                Text(title)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                AppearanceSelectionRadio(isSelected: isSelected)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text("模式：\(title)"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct AppearanceAccentSwatchButton: View {
    @Environment(ThemeManager.self) private var theme

    let option: AccentColorOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(theme.accentSwatch(option).opacity(0.28))
                        .frame(width: 50, height: 50)
                }
                Circle()
                    .fill(theme.accentSwatch(option))
                    .frame(width: 38, height: 38)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("appearanceAccentOption-\(option.rawValue)")
        .accessibilityLabel(Text("主色：\(option.appearanceDisplayName)"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct AppearanceTextureOptionCard: View {
    let texture: BackgroundTexture
    let title: String
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppearanceTextureOptionLabel(
                texture: texture,
                title: title,
                isSelected: isSelected,
                customImageURL: nil,
                customImageRevision: 0
            )
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text("背景纹理：\(title)"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct AppearanceTextureOptionLabel: View {
    @Environment(ThemeManager.self) private var theme

    let texture: BackgroundTexture
    let title: String
    let isSelected: Bool
    let customImageURL: URL?
    let customImageRevision: Int

    var body: some View {
        VStack(spacing: 8) {
            AppearanceBackgroundTexturePreview(
                mode: theme.mode,
                accentColor: theme.accentColor,
                texture: texture,
                customImageURL: customImageURL,
                customImageRevision: customImageRevision
            )
            .frame(maxWidth: .infinity)
            .frame(height: AppearancePreviewMetrics.texturePreviewHeight)
            .overlay(selectionBorder)
            .appearancePreviewMeasurementIdentifier("appearanceTexturePreview-\(texture.rawValue)")

            Text(title)
                .font(AppTypography.caption.weight(.semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(height: AppearancePreviewMetrics.textureOptionHeight, alignment: .top)
        .contentShape(Rectangle())
    }

    private var selectionBorder: some View {
        RoundedRectangle(cornerRadius: AppearancePreviewMetrics.cornerRadius, style: .continuous)
            .stroke(
                isSelected ? theme.accent : theme.separator.opacity(0.65),
                lineWidth: isSelected ? 2 : 1
            )
    }
}

struct AppearanceImageDisplayOptionCard: View {
    @Environment(ThemeManager.self) private var theme

    let mode: ImageDisplayMode
    let title: String
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                AppearanceImageDisplayPreview(mode: mode)
                    .frame(height: 132)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(
                                isSelected ? theme.accent : Color.clear,
                                lineWidth: isSelected ? 2 : 0
                            )
                    )

                Text(title)
                    .font(AppTypography.button)
                    .foregroundStyle(theme.primaryText)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text("图片展示：\(title)"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct AppearanceSelectionRadio: View {
    @Environment(ThemeManager.self) private var theme

    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? theme.accent : theme.primaryText, lineWidth: 2)
                .frame(width: 24, height: 24)
            if isSelected {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 13, height: 13)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct AppearanceThemeOverviewPreview: View {
    let mode: ThemeMode
    let accentColor: AccentColorOption
    let texture: BackgroundTexture
    let customImageURL: URL?
    let customImageRevision: Int

    private var tokens: AppThemeTokens {
        AppThemeTokens.resolve(mode: mode, accentColor: accentColor)
    }

    var body: some View {
        ZStack {
            AppearancePreviewCanvas(
                tokens: tokens,
                texture: texture,
                customImageURL: customImageURL,
                customImageRevision: customImageRevision
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tokens.primaryText.opacity(0.72))
                        .frame(width: 22, height: 5)
                    Spacer()
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tokens.secondaryText.opacity(0.36))
                        .frame(width: 10, height: 5)
                }
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tokens.secondaryText.opacity(0.46))
                    .frame(width: 42, height: 5)
                Spacer()
                Circle()
                    .fill(tokens.accent)
                    .frame(width: 24, height: 24)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(10)
        }
        .overlay(
            RoundedRectangle(
                cornerRadius: AppearancePreviewMetrics.cornerRadius, style: .continuous
            )
            .stroke(tokens.accent.opacity(texture == .customImage ? 0.55 : 0.22), lineWidth: 1)
        )
    }
}

private struct AppearanceBackgroundTexturePreview: View {
    let mode: ThemeMode
    let accentColor: AccentColorOption
    let texture: BackgroundTexture
    let customImageURL: URL?
    let customImageRevision: Int

    private var tokens: AppThemeTokens {
        AppThemeTokens.resolve(mode: mode, accentColor: accentColor)
    }

    var body: some View {
        AppearancePreviewCanvas(
            tokens: tokens,
            texture: texture,
            customImageURL: customImageURL,
            customImageRevision: customImageRevision
        )
    }
}

private struct AppearancePreviewCanvas: View {
    let tokens: AppThemeTokens
    let texture: BackgroundTexture
    let customImageURL: URL?
    let customImageRevision: Int

    var body: some View {
        GeometryReader { proxy in
            BackgroundTextureSurface(
                canvasBackground: tokens.canvasBackground,
                texture: texture,
                textureColor: tokens.homeTextureColor,
                customImageURL: customImageURL,
                customImageRevision: customImageRevision,
                customBackgroundOverlay: tokens.customBackgroundOverlay
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: AppearancePreviewMetrics.cornerRadius,
                    style: .continuous
                )
            )
        }
        .clipped()
    }
}

private struct AppearanceImageDisplayPreview: View {
    @Environment(ThemeManager.self) private var theme

    let mode: ImageDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(theme.secondaryText.opacity(0.78))
                .frame(width: 66, height: 10)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(theme.secondaryText.opacity(0.58))
                .frame(maxWidth: .infinity)
                .frame(height: 8)

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(photoFill)

                if mode == .scroll {
                    scrollPhotoShapes
                } else {
                    carouselDots
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(13)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(theme.previewMuted.opacity(theme.mode == .dark ? 0.28 : 0.34))
        )
    }

    private var photoFill: LinearGradient {
        LinearGradient(
            colors: [
                MoodPalette.color(.normal, mode: theme.mode).opacity(
                    theme.mode == .dark ? 0.55 : 0.28),
                MoodPalette.color(.normal, mode: theme.mode).opacity(
                    theme.mode == .dark ? 0.22 : 0.16),
            ],
            startPoint: .bottomLeading,
            endPoint: .topTrailing
        )
    }

    private var scrollPhotoShapes: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.sheetPanelBackground.opacity(0.26))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.sheetPanelBackground.opacity(0.20))
                .frame(width: 58)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var carouselDots: some View {
        HStack(spacing: 8) {
            Circle().fill(theme.primaryText.opacity(0.85))
            Circle().fill(theme.primaryText.opacity(0.35))
            Circle().fill(theme.primaryText.opacity(0.35))
        }
        .frame(width: 66, height: 25)
        .background(
            Capsule()
                .fill(theme.sheetPanelBackground.opacity(theme.mode == .dark ? 0.34 : 0.55))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 12)
    }
}

private extension AccentColorOption {
    var appearanceDisplayName: String {
        switch self {
        case .purple: "紫色"
        case .red: "红色"
        case .orange: "橙色"
        case .green: "绿色"
        case .cyan: "青色"
        case .violet: "紫罗兰"
        }
    }
}
