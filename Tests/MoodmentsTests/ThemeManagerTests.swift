import SwiftUI
import UIKit
import XCTest
@testable import Moodments

@MainActor
final class ThemeManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var customBackgroundImageDirectoryURL: URL!

    override func setUpWithError() throws {
        suiteName = "com.moodments.tests.themeManager.\(UUID().uuidString)"
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
        XCTAssertEqual(theme.canvasBackground, Color(hex: 0x121221))
        XCTAssertEqual(theme.bubbleBackground, Color(hex: 0x3A3A40))
        XCTAssertEqual(theme.bubbleTitleText, Color(hex: 0xEBEBED))
        XCTAssertEqual(theme.bubbleBodyText, Color(hex: 0xC7C7CC))
        XCTAssertEqual(theme.timelineRail, Color(hex: 0x2A2A38))
        XCTAssertEqual(theme.sheetPanelBackground, Color(hex: 0x2C2C2E))
        XCTAssertEqual(theme.separator, Color(hex: 0x3A3A3C))
        XCTAssertEqual(theme.previewMuted, Color(hex: 0x3A3A3C))
        XCTAssertEqual(theme.secondaryText, Color(hex: 0x8E8E93))
        XCTAssertEqual(theme.mutedText, Color(hex: 0x8E8E93))
        XCTAssertEqual(theme.homeContextSurfaceTint, Color(hex: 0x121221).opacity(0.22))

        theme.setMode(.light)

        XCTAssertEqual(theme.tokens.mode, .light)
        XCTAssertEqual(theme.canvasBackground, Color(hex: 0xF2F2F6))
        XCTAssertEqual(theme.bubbleBackground, Color(hex: 0xFFFFFF))
        XCTAssertEqual(theme.bubbleTitleText, Color(hex: 0x0D0C2B))
        XCTAssertEqual(theme.bubbleBodyText, Color(hex: 0x6C6C70))
        XCTAssertEqual(theme.timelineRail, Color(hex: 0xE3E2EA))
        XCTAssertEqual(theme.sheetPanelBackground, Color(hex: 0xFFFFFF))
        XCTAssertEqual(theme.separator, Color(hex: 0xE5E5EA))
        XCTAssertEqual(theme.previewMuted, Color(hex: 0xE5E5EA))
        XCTAssertEqual(theme.secondaryText, Color(hex: 0x6C6C70))
        XCTAssertEqual(theme.mutedText, Color(hex: 0x8E8E93))
        XCTAssertEqual(theme.homeContextSurfaceTint, Color(hex: 0xF2F2F6).opacity(0.12))
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
        XCTAssertEqual(theme.customBackgroundOverlay, Color(hex: 0xF2F2F6).opacity(0.10))
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
