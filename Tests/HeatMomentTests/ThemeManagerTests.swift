import SwiftUI
import UIKit
import XCTest
@testable import HeatMoment

@MainActor
final class ThemeManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var customBackgroundImageDirectoryURL: URL!

    override func setUpWithError() throws {
        suiteName = "com.heatmoment.tests.themeManager.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        customBackgroundImageDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
            .appendingPathComponent("Appearance", isDirectory: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        if FileManager.default.fileExists(atPath: customBackgroundImageDirectoryURL.path) {
            do {
                try FileManager.default.removeItem(at: customBackgroundImageDirectoryURL)
            } catch {
                assertionFailure("ThemeManagerTests 自定义背景图目录清理失败：\(error)")
            }
        }
        customBackgroundImageDirectoryURL = nil
        defaults = nil
        suiteName = nil
    }

    func testCustomBackgroundImageWriteSwitchesTextureAfterFileWriteSucceeds() async {
        let store = makeStore()
        let theme = ThemeManager(store: store)

        await theme.setCustomBackgroundImageData(Self.makeSyntheticImageData())

        XCTAssertEqual(theme.backgroundTexture, .customImage)
        XCTAssertEqual(theme.customBackgroundImageURL, store.customBackgroundImageFileURL)
        XCTAssertEqual(theme.customBackgroundImageRevision, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: store.customBackgroundImageFileURL.path)
        )
        XCTAssertFalse(theme.appearanceSaveFailed)
    }

    func testCustomBackgroundImageWriteFailureKeepsPreviousTexture() async {
        let store = makeStore(simulateSaveFailure: true)
        let theme = ThemeManager(store: store)

        await theme.setCustomBackgroundImageData(Self.makeSyntheticImageData())

        XCTAssertEqual(theme.backgroundTexture, AppearancePreference.default.backgroundTexture)
        XCTAssertNil(theme.customBackgroundImageURL)
        XCTAssertEqual(theme.customBackgroundImageRevision, 0)
        XCTAssertTrue(theme.appearanceSaveFailed)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.customBackgroundImageFileURL.path)
        )
    }

    func testCustomImagePreferenceWithMissingFileCorrectsToDefaultTexture() throws {
        let store = makeStore()
        try store.save(
            AppearancePreference(
                mode: .dark,
                accentColor: .violet,
                backgroundTexture: .customImage,
                imageDisplayMode: .scroll
            )
        )

        let theme = ThemeManager(store: store)

        XCTAssertEqual(theme.backgroundTexture, AppearancePreference.default.backgroundTexture)
        XCTAssertNil(theme.customBackgroundImageURL)
        XCTAssertFalse(theme.appearanceSaveFailed)
        XCTAssertTrue(theme.customBackgroundImageRecovered)
    }

    func testSettingFeaturedBackgroundSelectsFeaturedTextureAndPersists() {
        let store = makeStore()
        let theme = ThemeManager(store: store)

        theme.setFeaturedBackground(.softBlocks)

        XCTAssertEqual(theme.backgroundTexture, .featured)
        XCTAssertEqual(theme.featuredBackground, .softBlocks)
        XCTAssertFalse(theme.appearanceSaveFailed)

        let restoredTheme = ThemeManager(store: store)
        XCTAssertEqual(restoredTheme.backgroundTexture, .featured)
        XCTAssertEqual(restoredTheme.featuredBackground, .softBlocks)
    }

    func testModeScopedThemeTokensResolveFromCurrentMode() {
        let theme = ThemeManager(store: makeStore())

        XCTAssertEqual(theme.tokens.mode, .dark)
        XCTAssertEqual(theme.canvasBackground, Color(hex: 0x14151A))
        XCTAssertEqual(theme.bubbleBackground, Color(hex: 0x272A31))
        XCTAssertEqual(theme.bubbleTitleText, Color(hex: 0xF5F7FA))
        XCTAssertEqual(theme.bubbleBodyText, Color(hex: 0xB7BCC7))
        XCTAssertEqual(theme.timelineRail, Color(hex: 0x2C2E35))
        XCTAssertEqual(theme.sheetBackground, Color(hex: 0x17181C))
        XCTAssertEqual(theme.sheetPanelBackground, Color(hex: 0x23252B))
        XCTAssertEqual(theme.separator, Color(hex: 0x353840))
        XCTAssertEqual(theme.chipFill, Color(hex: 0x30333A))
        XCTAssertEqual(theme.previewMuted, Color(hex: 0x353840))
        XCTAssertEqual(theme.primaryText, Color(hex: 0xF5F7FA))
        XCTAssertEqual(theme.secondaryText, Color(hex: 0xA0A6B2))
        XCTAssertEqual(theme.mutedText, Color(hex: 0x878E9B))
        XCTAssertEqual(theme.neutralIconStroke, Color(hex: 0xECEFF4))
        XCTAssertEqual(theme.heatmapEmptyCell, Color(hex: 0x3B3D45))
        XCTAssertEqual(theme.featuredBackgroundOverlay, Color(hex: 0x14151A).opacity(0.16))
        XCTAssertEqual(theme.topChromeOverlay, Color(hex: 0x14151A).opacity(0.42))
        XCTAssertEqual(theme.homeContextSurfaceTint, Color(hex: 0x14151A).opacity(0.20))
        XCTAssertEqual(theme.heatmapSeparator, Color(hex: 0x2C2E35).opacity(0.64))

        theme.setMode(.light)

        XCTAssertEqual(theme.tokens.mode, .light)
        XCTAssertEqual(theme.canvasBackground, Color(hex: 0xF5F5F7))
        XCTAssertEqual(theme.bubbleBackground, Color(hex: 0xFFFFFF))
        XCTAssertEqual(theme.bubbleTitleText, Color(hex: 0x111318))
        XCTAssertEqual(theme.bubbleBodyText, Color(hex: 0x60646E))
        XCTAssertEqual(theme.timelineRail, Color(hex: 0xD8DAE0))
        XCTAssertEqual(theme.sheetBackground, Color(hex: 0xF4F5F7))
        XCTAssertEqual(theme.sheetPanelBackground, Color(hex: 0xFFFFFF))
        XCTAssertEqual(theme.separator, Color(hex: 0xE3E5EA))
        XCTAssertEqual(theme.chipFill, Color(hex: 0xECEEF3))
        XCTAssertEqual(theme.previewMuted, Color(hex: 0xE3E5EA))
        XCTAssertEqual(theme.primaryText, Color(hex: 0x111318))
        XCTAssertEqual(theme.secondaryText, Color(hex: 0x666B76))
        XCTAssertEqual(theme.mutedText, Color(hex: 0x8B909B))
        XCTAssertEqual(theme.neutralIconStroke, Color(hex: 0x3A3D45))
        XCTAssertEqual(theme.heatmapEmptyCell, Color(hex: 0xD7D9E0))
        XCTAssertEqual(theme.featuredBackgroundOverlay, Color(hex: 0xF5F5F7).opacity(0.10))
        XCTAssertEqual(theme.topChromeOverlay, Color(hex: 0xF5F5F7).opacity(0.30))
        XCTAssertEqual(theme.homeContextSurfaceTint, Color(hex: 0xF5F5F7).opacity(0.14))
        XCTAssertEqual(theme.heatmapSeparator, Color(hex: 0xD8DAE0).opacity(0.64))
    }

    func testAccentDerivedThemeTokensFollowCurrentAccentAndMode() {
        let theme = ThemeManager(store: makeStore())

        XCTAssertEqual(theme.accent, Color(hex: 0xB678F5))
        XCTAssertEqual(theme.accentSwatch(.purple), Color(hex: 0x5E5BE6))
        XCTAssertEqual(
            theme.selectionFill,
            Color(hex: 0xB678F5).opacity(0.08)
        )
        XCTAssertEqual(theme.onAccentText, Color(hex: 0x0D0C2B))
        XCTAssertEqual(theme.onAccentSecondaryText, Color(hex: 0x0D0C2B).opacity(0.86))
        XCTAssertEqual(
            theme.homeTextureColor,
            Color(hex: 0xB678F5).opacity(0.10)
        )

        theme.setAccentColor(.red)

        XCTAssertEqual(theme.accent, Color(hex: 0xFC5447))
        XCTAssertEqual(theme.onAccentText, Color(hex: 0x0D0C2B))
        XCTAssertEqual(
            theme.accentDisabledFill,
            Color(hex: 0xFC5447).opacity(0.45)
        )
        XCTAssertEqual(
            theme.selectedMonthFill,
            Color(hex: 0xFC5447).opacity(0.14)
        )

        theme.setMode(.light)

        XCTAssertEqual(theme.accent, Color(hex: 0xE9604F))
        XCTAssertEqual(theme.accentSwatch(.red), Color(hex: 0xE9604F))
        XCTAssertEqual(
            theme.homeTextureColor,
            Color(hex: 0xE9604F).opacity(0.14)
        )
        XCTAssertEqual(theme.customBackgroundOverlay, Color(hex: 0xF5F5F7).opacity(0.14))
    }

    func testAccentForegroundMaintainsReadableContrastAcrossAccentMatrix() {
        for mode in ThemeMode.allCases {
            for accent in AccentColorOption.allCases {
                let expectedHex = Self.expectedAccentForegroundHex(accent, mode: mode)
                XCTAssertEqual(
                    AccentPalette.onText(accent, mode: mode),
                    Color(hex: expectedHex),
                    "\(mode)/\(accent) 应使用可读的强调色前景"
                )
                XCTAssertGreaterThanOrEqual(
                    AccentPalette.contrastRatio(
                        foreground: expectedHex,
                        background: AccentPalette.hexValue(accent, mode: mode)
                    ),
                    4.5,
                    "\(mode)/\(accent) 强调色前景对比度不足"
                )
            }
        }
    }

    private static func expectedAccentForegroundHex(
        _ accent: AccentColorOption,
        mode: ThemeMode
    ) -> UInt32 {
        switch (accent, mode) {
        case (.purple, _), (.violet, .light): 0xFFFFFF
        case (.green, .light): 0x000000
        default: 0x0D0C2B
        }
    }

    func testFixedCommercialTokensDoNotFollowModeOrAccent() {
        let theme = ThemeManager(store: makeStore())
        let commercialTokens = (
            red: theme.commercialRed,
            background: theme.commercialBackground,
            panelBackground: theme.commercialPanelBackground,
            primaryText: theme.commercialPrimaryText,
            secondaryText: theme.commercialSecondaryText,
            logoFill: theme.commercialLogoFill
        )

        for mode in ThemeMode.allCases {
            theme.setMode(mode)
            for accent in AccentColorOption.allCases {
                theme.setAccentColor(accent)
                XCTAssertEqual(theme.commercialRed, commercialTokens.red)
                XCTAssertEqual(theme.commercialBackground, commercialTokens.background)
                XCTAssertEqual(theme.commercialPanelBackground, commercialTokens.panelBackground)
                XCTAssertEqual(theme.commercialPrimaryText, commercialTokens.primaryText)
                XCTAssertEqual(theme.commercialSecondaryText, commercialTokens.secondaryText)
                XCTAssertEqual(theme.commercialLogoFill, commercialTokens.logoFill)
            }
        }
    }

    private func makeStore(simulateSaveFailure: Bool = false) -> AppearanceStore {
        AppearanceStore(
            defaults: defaults,
            customBackgroundImageDirectoryURL: customBackgroundImageDirectoryURL,
            simulateSaveFailure: simulateSaveFailure
        )
    }

    private static func makeSyntheticImageData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        guard let data = image.pngData() else {
            XCTFail("合成测试图片编码失败")
            return Data()
        }
        return data
    }
}
