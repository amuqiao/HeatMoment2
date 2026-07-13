import SwiftUI
import XCTest
@testable import HeatMoment

/// 心情色独立性验收（见 `docs/product-mental-model.md` 公理1「心情色一致性」、
/// `docs/current/implementation-truth.md` §5.3.6/§5.4，`docs/plans/implementation-plan.md` 阶段6）：
/// `MoodPalette.color(_:mode:)` 的签名内没有 `AccentColorOption` 参数——这是「切主色时
/// 心情色不变」的结构性保证。
final class MoodPaletteTests: XCTestCase {
    /// 对暗色模式，8 情绪心情色在切换任意主色前后必须恒等。
    @MainActor
    func testMoodColorsUnaffectedByAccentColorSwitchInDarkMode() {
        let theme = ThemeManager(store: Self.makeIsolatedStore())
        let baseline = Mood.allCases.map { MoodPalette.color($0, mode: theme.mode) }

        for accent in AccentColorOption.allCases {
            theme.setAccentColor(accent)
            let current = Mood.allCases.map { MoodPalette.color($0, mode: theme.mode) }
            XCTAssertEqual(current, baseline, "切主色到 \(accent) 后心情色不应变化")
        }
    }

    /// 同上，亮色模式同样成立（模式本身固定为亮色，只变化主色）。
    @MainActor
    func testMoodColorsUnaffectedByAccentColorSwitchInLightMode() {
        let theme = ThemeManager(store: Self.makeIsolatedStore())
        theme.setMode(.light)
        let baseline = Mood.allCases.map { MoodPalette.color($0, mode: theme.mode) }

        for accent in AccentColorOption.allCases {
            theme.setAccentColor(accent)
            let current = Mood.allCases.map { MoodPalette.color($0, mode: theme.mode) }
            XCTAssertEqual(current, baseline, "亮色模式下切主色到 \(accent) 后心情色不应变化")
        }
    }

    /// 危险色同样与主色无关（`ThemeManager.danger` 来自固定语义 token）。
    @MainActor
    func testDangerColorUnaffectedByAccentColorSwitch() {
        let theme = ThemeManager(store: Self.makeIsolatedStore())
        let baseline = theme.danger

        for accent in AccentColorOption.allCases {
            theme.setAccentColor(accent)
            XCTAssertEqual(theme.danger, baseline, "切主色到 \(accent) 后危险色不应变化")
        }
    }

    /// 「正常」情绪亮色态取真机实测精确值 `#58BBB3`（见 docs/current/implementation-truth.md §5.2.1/§5.4）。
    func testNormalMoodLightColorMatchesMeasuredValue() {
        XCTAssertEqual(MoodPalette.color(.normal, mode: .light), Color(hex: 0x58BBB3))
    }

    /// 「正常」情绪暗色态取真机实测精确值 `#15BEB4`（见 docs/current/implementation-truth.md §5.2.1）。
    func testNormalMoodDarkColorMatchesMeasuredValue() {
        XCTAssertEqual(MoodPalette.color(.normal, mode: .dark), Color(hex: 0x15BEB4))
    }

    /// 模式感知：暗/亮两态在「正常」情绪上应不同（其余 7 个情绪当前两态取值相同，属已知
    /// `[设计决策待确认]` 事项，见 `MoodPalette` 头部注释，不在本测试断言范围）。
    func testNormalMoodColorDiffersByMode() {
        XCTAssertNotEqual(
            MoodPalette.color(.normal, mode: .dark),
            MoodPalette.color(.normal, mode: .light)
        )
    }

    /// 每个测试独立的隔离 `AppearanceStore`（不落到共享 `UserDefaults.standard`，避免测试间
    /// 相互污染，也避免影响真实用户默认域）。
    private static func makeIsolatedStore() -> AppearanceStore {
        let suiteName = "com.heatmoment.tests.moodColorPalette.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return AppearanceStore(defaults: defaults)
    }
}
