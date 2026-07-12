import Foundation
import SwiftUI

/// 当前模式和主色解析后的稳定运行时 token。
///
/// 颜色系统先表达产品语义，再由 `mode` 决定暗/亮取值：
/// - 品牌画布：承载首页时间轴的记忆叙事。
/// - 记忆对象：承载气泡、节点、照片、标签等记录本身。
/// - 任务容器：承载 sheet、设置、编辑器和选择任务。
/// - 行动强调：只表达可行动、选中和聚焦，跟随主色。
/// - 独立语义：心情色、危险色、商业固定色，不跟随主色。
struct AppThemeTokens {
    let mode: ThemeMode
    let accent: Color

    let canvasBackground: Color
    let bubbleBackground: Color
    let bubbleTitleText: Color
    let bubbleBodyText: Color
    let timelineRail: Color

    let sheetBackground: Color
    let sheetPanelBackground: Color
    let separator: Color
    let chipFill: Color

    let primaryText: Color
    let secondaryText: Color
    let mutedText: Color

    let neutralIconStroke: Color
    let heatmapEmptyCell: Color

    let selectionFill: Color
    let accentDisabledFill: Color
    let selectedMonthFill: Color
    let homeTextureColor: Color
    let customBackgroundOverlay: Color
    let topChromeOverlay: Color
    let homeContextSurfaceTint: Color
    let heatmapSeparator: Color
    let previewBackground: Color
    let previewMuted: Color
    let floatingActionShadow: Color

    let danger: Color
    let commercialRed: Color
    let commercialBackground: Color
    let commercialPanelBackground: Color
    let commercialPrimaryText: Color
    let commercialSecondaryText: Color
    let commercialLogoFill: Color
    let onAccentText: Color
    let onAccentSecondaryText: Color
    let onDangerText: Color
    let onCommercialText: Color
    let imageViewerBackground: Color
    let imageViewerChromeScrim: Color
    let onImageViewerChrome: Color

    static func resolve(mode: ThemeMode, accentColor: AccentColorOption) -> Self {
        let accent = AccentPalette.color(accentColor, mode: mode)
        return Self(
            mode: mode,
            accent: accent,
            canvasBackground: BrandCanvasPalette.canvasBackground(mode),
            bubbleBackground: MemoryObjectPalette.bubbleBackground(mode),
            bubbleTitleText: MemoryObjectPalette.bubbleTitleText(mode),
            bubbleBodyText: MemoryObjectPalette.bubbleBodyText(mode),
            timelineRail: BrandCanvasPalette.timelineRail(mode),
            sheetBackground: TaskContainerPalette.sheetBackground(mode),
            sheetPanelBackground: TaskContainerPalette.sheetPanelBackground(mode),
            separator: TaskContainerPalette.separator(mode),
            chipFill: TaskContainerPalette.chipFill(mode),
            primaryText: TaskContainerPalette.primaryText(mode),
            secondaryText: TaskContainerPalette.secondaryText(mode),
            mutedText: TaskContainerPalette.mutedText(mode),
            neutralIconStroke: TaskContainerPalette.neutralIconStroke(mode),
            heatmapEmptyCell: MemoryObjectPalette.heatmapEmptyCell(mode),
            selectionFill: AccentPalette.selectionFill(accent: accent),
            accentDisabledFill: AccentPalette.disabledFill(accent: accent),
            selectedMonthFill: AccentPalette.selectedMonthFill(accent: accent),
            homeTextureColor: AccentPalette.homeTextureColor(accent: accent, mode: mode),
            customBackgroundOverlay: BrandCanvasPalette.customBackgroundOverlay(mode),
            topChromeOverlay: BrandCanvasPalette.topChromeOverlay(mode),
            homeContextSurfaceTint: BrandCanvasPalette.contextSurfaceTint(mode),
            heatmapSeparator: BrandCanvasPalette.heatmapSeparator(mode),
            previewBackground: TaskContainerPalette.previewBackground(mode),
            previewMuted: TaskContainerPalette.previewMuted(mode),
            floatingActionShadow: FixedIntentColor.floatingActionShadow,
            danger: FixedIntentColor.danger,
            commercialRed: FixedIntentColor.commercialRed,
            commercialBackground: FixedIntentColor.commercialBackground,
            commercialPanelBackground: FixedIntentColor.commercialPanelBackground,
            commercialPrimaryText: FixedIntentColor.commercialPrimaryText,
            commercialSecondaryText: FixedIntentColor.commercialSecondaryText,
            commercialLogoFill: FixedIntentColor.commercialLogoFill,
            onAccentText: AccentPalette.onText(accentColor, mode: mode),
            onAccentSecondaryText: AccentPalette.onSecondaryText(accentColor, mode: mode),
            onDangerText: FixedIntentColor.onDangerText,
            onCommercialText: FixedIntentColor.onCommercialText,
            imageViewerBackground: FixedIntentColor.imageViewerBackground,
            imageViewerChromeScrim: FixedIntentColor.imageViewerChromeScrim,
            onImageViewerChrome: FixedIntentColor.onImageViewerChrome
        )
    }

    func accentSwatch(_ option: AccentColorOption) -> Color {
        AccentPalette.color(option, mode: mode)
    }
}

// MARK: - 品牌画布

enum BrandCanvasPalette {
    static func canvasBackground(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0x121221) : Color(hex: 0xF2F2F6)
    }

    static func timelineRail(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0x2A2A38) : Color(hex: 0xE3E2EA)
    }

    static func customBackgroundOverlay(_ mode: ThemeMode) -> Color {
        canvasBackground(mode).opacity(mode == .dark ? 0.18 : 0.10)
    }

    static func topChromeOverlay(_ mode: ThemeMode) -> Color {
        canvasBackground(mode).opacity(0.36)
    }

    static func contextSurfaceTint(_ mode: ThemeMode) -> Color {
        canvasBackground(mode).opacity(mode == .dark ? 0.22 : 0.12)
    }

    static func heatmapSeparator(_ mode: ThemeMode) -> Color {
        timelineRail(mode).opacity(0.55)
    }
}

// MARK: - 记忆对象

enum MemoryObjectPalette {
    static func bubbleBackground(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0x3A3A40) : Color(hex: 0xFFFFFF)
    }

    static func bubbleTitleText(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0xEBEBED) : Color(hex: 0x0D0C2B)
    }

    static func bubbleBodyText(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0xC7C7CC) : Color(hex: 0x6C6C70)
    }

    static func heatmapEmptyCell(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0x454547) : Color(hex: 0xD1D1D6)
    }
}

// MARK: - 任务容器

enum TaskContainerPalette {
    static func sheetBackground(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0x1C1C1E) : Color(hex: 0xF2F2F7)
    }

    static func sheetPanelBackground(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0x2C2C2E) : Color(hex: 0xFFFFFF)
    }

    static func separator(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0x3A3A3C) : Color(hex: 0xE5E5EA)
    }

    static func chipFill(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0x48484B) : Color(hex: 0xE9E9EC)
    }

    static func primaryText(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0xF2F2F7) : Color(hex: 0x0D0C2B)
    }

    static func secondaryText(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0x8E8E93) : Color(hex: 0x6C6C70)
    }

    static func mutedText(_: ThemeMode) -> Color {
        Color(hex: 0x8E8E93)
    }

    static func neutralIconStroke(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0xEBEBF5) : Color(hex: 0x3C3C43)
    }

    static func previewBackground(_ mode: ThemeMode) -> Color {
        sheetPanelBackground(mode)
    }

    static func previewMuted(_ mode: ThemeMode) -> Color {
        separator(mode)
    }
}

// MARK: - 行动强调主色

enum AccentPalette {
    static func color(_ option: AccentColorOption, mode: ThemeMode) -> Color {
        switch (option, mode) {
        case (.purple, _): Color(hex: 0x5E5BE6)
        case (.red, .dark): Color(hex: 0xFC5447)
        case (.red, .light): Color(hex: 0xE9604F)
        case (.orange, .dark): Color(hex: 0xF7A213)
        case (.orange, .light): Color(hex: 0xF39911)
        case (.green, .dark): Color(hex: 0x2DAD74)
        case (.green, .light): Color(hex: 0x228859)
        case (.cyan, _): Color(hex: 0x00C7BD)
        case (.violet, .dark): Color(hex: 0xB678F5)
        case (.violet, .light): Color(hex: 0x8E51AE)
        }
    }

    static func selectionFill(accent: Color) -> Color {
        accent.opacity(0.08)
    }

    static func disabledFill(accent: Color) -> Color {
        accent.opacity(0.45)
    }

    static func selectedMonthFill(accent: Color) -> Color {
        accent.opacity(0.14)
    }

    static func homeTextureColor(accent: Color, mode: ThemeMode) -> Color {
        accent.opacity(mode == .dark ? 0.10 : 0.14)
    }

    static func onText(_ option: AccentColorOption, mode: ThemeMode) -> Color {
        let accentHex = hexValue(option, mode: mode)
        let preferred = preferredOnTextHex(option, mode: mode)
        let preferredContrast = contrastRatio(foreground: preferred, background: accentHex)
        if preferredContrast >= 4.5 {
            return Color(hex: preferred)
        }
        return Color(hex: FixedIntentColor.highContrastDarkOnAccentTextHex)
    }

    static func onSecondaryText(_ option: AccentColorOption, mode: ThemeMode) -> Color {
        onText(option, mode: mode).opacity(0.86)
    }

    static func contrastRatio(foreground: UInt32, background: UInt32) -> Double {
        let foregroundLuminance = relativeLuminance(foreground)
        let backgroundLuminance = relativeLuminance(background)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func hexValue(_ option: AccentColorOption, mode: ThemeMode) -> UInt32 {
        switch (option, mode) {
        case (.purple, _): 0x5E5BE6
        case (.red, .dark): 0xFC5447
        case (.red, .light): 0xE9604F
        case (.orange, .dark): 0xF7A213
        case (.orange, .light): 0xF39911
        case (.green, .dark): 0x2DAD74
        case (.green, .light): 0x228859
        case (.cyan, _): 0x00C7BD
        case (.violet, .dark): 0xB678F5
        case (.violet, .light): 0x8E51AE
        }
    }

    private static func preferredOnTextHex(_ option: AccentColorOption, mode: ThemeMode) -> UInt32 {
        switch (option, mode) {
        case (.purple, _), (.violet, .light):
            FixedIntentColor.lightOnAccentTextHex
        default:
            FixedIntentColor.darkOnAccentTextHex
        }
    }

    private static func relativeLuminance(_ hex: UInt32) -> Double {
        let red = linearComponent(Double((hex >> 16) & 0xFF) / 255)
        let green = linearComponent(Double((hex >> 8) & 0xFF) / 255)
        let blue = linearComponent(Double(hex & 0xFF) / 255)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private static func linearComponent(_ component: Double) -> Double {
        component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
}

// MARK: - 独立固定语义

enum FixedIntentColor {
    static let danger = Color(hex: 0xFC5447)
    static let commercialRed = Color(hex: 0xFC5447)
    static let commercialBackground = Color(hex: 0xF2F2F7)
    static let commercialPanelBackground = Color(hex: 0xFFFFFF)
    static let commercialPrimaryText = Color(hex: 0x0D0C2B)
    static let commercialSecondaryText = Color(hex: 0x6C6C70)
    static let commercialLogoFill = Color(hex: 0x010048)
    static let lightOnAccentTextHex: UInt32 = 0xFFFFFF
    static let darkOnAccentTextHex: UInt32 = 0x0D0C2B
    static let highContrastDarkOnAccentTextHex: UInt32 = 0x000000
    static let lightOnAccentText = Color.white
    static let darkOnAccentText = Color(hex: 0x0D0C2B)
    static let onDangerText = Color.white
    static let onCommercialText = Color.white
    static let imageViewerBackground = Color.black
    static let imageViewerChromeScrim = Color.black.opacity(0.4)
    static let onImageViewerChrome = Color.white
    static let floatingActionShadow = Color.black.opacity(0.20)
}
