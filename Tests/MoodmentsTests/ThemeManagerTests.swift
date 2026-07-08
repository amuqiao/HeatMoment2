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

    func testModeScopedThemeTokensResolveFromCurrentMode() {
        let theme = ThemeManager(store: makeStore())

        XCTAssertEqual(theme.sheetPanelBackground, Color(hex: 0x2C2C2E))
        XCTAssertEqual(theme.separator, Color(hex: 0x3A3A3C))
        XCTAssertEqual(theme.previewMuted, Color(hex: 0x3A3A3C))
        XCTAssertEqual(theme.secondaryText, SemanticColor.secondaryText)
        XCTAssertEqual(theme.mutedText, SemanticColor.mutedText)

        theme.setMode(.light)

        XCTAssertEqual(theme.sheetPanelBackground, Color(hex: 0xFFFFFF))
        XCTAssertEqual(theme.separator, Color(hex: 0xE5E5EA))
        XCTAssertEqual(theme.previewMuted, Color(hex: 0xE5E5EA))
    }

    func testAccentDerivedThemeTokensFollowCurrentAccentAndMode() {
        let theme = ThemeManager(store: makeStore())

        XCTAssertEqual(
            theme.selectionFill,
            Color(hex: 0xB678F5).opacity(0.08)
        )
        XCTAssertEqual(
            theme.homeTextureColor,
            Color(hex: 0xB678F5).opacity(0.10)
        )

        theme.setAccentColor(.red)

        XCTAssertEqual(
            theme.accentDisabledFill,
            Color(hex: 0xFC5447).opacity(0.45)
        )
        XCTAssertEqual(
            theme.selectedMonthFill,
            Color(hex: 0xFC5447).opacity(0.14)
        )

        theme.setMode(.light)

        XCTAssertEqual(
            theme.homeTextureColor,
            Color(hex: 0xE9604F).opacity(0.14)
        )
        XCTAssertEqual(theme.customBackgroundOverlay, Color(hex: 0xF2F2F6).opacity(0.10))
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
