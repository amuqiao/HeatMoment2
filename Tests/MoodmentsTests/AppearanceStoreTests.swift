import XCTest
@testable import Moodments

/// `AppearanceStore` 持久化验收（见 `docs/current/local-data-architecture.md` §6、
/// `docs/current/implementation-truth.md` §5.3.7，`docs/plans/implementation-plan.md` 阶段6）：
/// round-trip、坏 rawValue 逐轴回落默认值 + 精确计数、缺失 key 不算「已修正」。
final class AppearanceStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var customBackgroundImageDirectoryURL: URL!

    override func setUpWithError() throws {
        suiteName = "com.moodments.tests.appearanceStore.\(UUID().uuidString)"
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
                assertionFailure("AppearanceStoreTests 自定义背景图目录清理失败：\(error)")
            }
        }
        customBackgroundImageDirectoryURL = nil
        defaults = nil
        suiteName = nil
    }

    /// 全新（无任何已写入 key）时，`load()` 返回产品默认值、`correctedCount == 0`
    /// （缺失 key 是正常初始态，不是坏配置）。
    func testLoadWithoutAnyStoredValueReturnsDefaultAndNoCorrection() {
        let store = makeStore()

        let (preference, correctedCount) = store.load()

        XCTAssertEqual(preference, AppearancePreference.default)
        XCTAssertEqual(correctedCount, 0)
    }

    /// 写入非默认值后原样读回（round-trip）。
    func testSaveThenLoadRoundTrips() throws {
        let store = makeStore()
        let preference = AppearancePreference(
            mode: .light,
            accentColor: .red,
            backgroundTexture: .featured,
            featuredBackground: .rainWindow,
            imageDisplayMode: .carousel
        )

        try store.save(preference)
        let (loaded, correctedCount) = store.load()

        XCTAssertEqual(loaded, preference)
        XCTAssertEqual(correctedCount, 0)
    }

    /// 单个轴写入无法解析的 rawValue（模拟坏配置/未来版本迁移遗留）：该轴回落默认值，
    /// 其余三轴保持写入值不变，`correctedCount == 1`。
    func testLoadWithSingleBadRawValueCorrectsOnlyThatAxis() throws {
        let store = makeStore()
        try store.save(
            AppearancePreference(
                mode: .light,
                accentColor: .green,
                backgroundTexture: .none,
                featuredBackground: .warmPaper,
                imageDisplayMode: .carousel
            )
        )
        defaults.set("not-a-real-accent-color", forKey: "com.moodments.appearance.accentColor")

        let (preference, correctedCount) = store.load()

        XCTAssertEqual(correctedCount, 1)
        XCTAssertEqual(
            preference.accentColor,
            AppearancePreference.default.accentColor,
            "坏值应回落默认主色"
        )
        XCTAssertEqual(preference.mode, .light, "未受影响的轴应保持原写入值")
        XCTAssertEqual(preference.backgroundTexture, .none)
        XCTAssertEqual(preference.featuredBackground, .warmPaper)
        XCTAssertEqual(preference.imageDisplayMode, .carousel)
    }

    /// 多个轴同时是坏值：精确计数为坏值轴数（本例 2 个：主色 + 背景纹理）。
    func testLoadWithMultipleBadRawValuesCorrectsExactCount() {
        defaults.set("bogus-accent", forKey: "com.moodments.appearance.accentColor")
        defaults.set("bogus-texture", forKey: "com.moodments.appearance.backgroundTexture")

        let (preference, correctedCount) = makeStore().load()

        XCTAssertEqual(correctedCount, 2)
        XCTAssertEqual(preference, AppearancePreference.default)
    }

    func testLoadWithBadFeaturedBackgroundCorrectsOnlyFeaturedAxis() throws {
        let store = makeStore()
        try store.save(
            AppearancePreference(
                mode: .light,
                accentColor: .cyan,
                backgroundTexture: .featured,
                featuredBackground: .peachDusk,
                imageDisplayMode: .carousel
            )
        )
        defaults.set(
            "not-a-featured-background",
            forKey: "com.moodments.appearance.featuredBackground"
        )

        let (preference, correctedCount) = store.load()

        XCTAssertEqual(correctedCount, 1)
        XCTAssertEqual(preference.mode, .light)
        XCTAssertEqual(preference.accentColor, .cyan)
        XCTAssertEqual(preference.backgroundTexture, .featured)
        XCTAssertEqual(
            preference.featuredBackground, AppearancePreference.default.featuredBackground)
        XCTAssertEqual(preference.imageDisplayMode, .carousel)
    }

    /// `simulateSaveFailure: true` 时 `save` 必抛错（供 UI 测试注入必失败场景使用）。
    func testSimulatedSaveFailureThrows() {
        let store = makeStore(simulateSaveFailure: true)

        XCTAssertThrowsError(try store.save(AppearancePreference.default)) { error in
            XCTAssertEqual(error as? AppearanceStoreError, .saveFailed)
        }
    }

    func testCustomBackgroundImageDataRoundTripsToFile() throws {
        let store = makeStore()
        let data = Data([0x01, 0x02, 0x03])

        try store.saveCustomBackgroundImageData(data)

        XCTAssertEqual(try store.loadCustomBackgroundImageData(), data)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: store.customBackgroundImageFileURL.path)
        )
    }

    func testCustomImagePreferenceRoundTrips() throws {
        let store = makeStore()
        let preference = AppearancePreference(
            mode: .dark,
            accentColor: .violet,
            backgroundTexture: .customImage,
            imageDisplayMode: .scroll
        )

        try store.save(preference)
        let (loaded, correctedCount) = store.load()

        XCTAssertEqual(loaded, preference)
        XCTAssertEqual(correctedCount, 0)
    }

    func testSimulatedSaveFailurePreventsCustomBackgroundImageWrite() {
        let store = makeStore(simulateSaveFailure: true)

        XCTAssertThrowsError(try store.saveCustomBackgroundImageData(Data([0x01]))) { error in
            XCTAssertEqual(error as? AppearanceStoreError, .saveFailed)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.customBackgroundImageFileURL.path)
        )
    }

    private func makeStore(simulateSaveFailure: Bool = false) -> AppearanceStore {
        AppearanceStore(
            defaults: defaults,
            customBackgroundImageDirectoryURL: customBackgroundImageDirectoryURL,
            simulateSaveFailure: simulateSaveFailure
        )
    }
}
