import Foundation
import SwiftUI

/// 应用内语言偏好（见 `docs/current/testing-architecture.md` §12.2、
/// `docs/current/implementation-truth.md` §4.11「语言」行、阶段7计划决策4）：zh-Hans / English /
/// 「跟随系统」三选一，`AppStorage` 持久化，驱动 `MoodmentsApp` 注入 `.environment(\.locale, ...)`。
///
/// **默认值 = `.zhHans`（而非「跟随系统」）**：本 App 面向的是中文用户为主的产品（开发区域
/// zh-Hans），且**既有大量 UI 测试按中文可见文案精确断言**（见阶段2–7各 UI 测试套件）——若默认
/// 跟随宿主机/模拟器的系统区域，测试渲染语言会随运行环境漂移（CI 机器、开发者模拟器的系统区域
/// 未必是中文），造成与本身无关的测试脆弱性。显式默认 `.zhHans` 使「未做任何语言设置」的初始
/// 状态在任何宿主环境下都确定性地渲染中文，与全部既有断言天然一致；用户仍可在设置页任意切到
/// English / 跟随系统。
enum LanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case zhHans
    case english
    case system

    /// `AppStorage`/`UserDefaults` 持久化 key（`LanguageSettingsView` 与 `MoodmentsApp` 共享
    /// 同一 key，读写同一份 `UserDefaults.standard`，天然保持一致，无需额外的变更通知管线）。
    static let storageKey = "com.moodments.languagePreference"

    var id: String { rawValue }

    /// 供非 View 上下文（如 `Mood.displayName`、`SyncStatus.displayText` 等无法读取
    /// `\.locale` 环境的纯函数/值类型计算属性）按当前语言偏好同步解析一次性文案，见
    /// `Localizable.xcstrings`。`key` 建议直接用中文源文案（可含插值）作为 catalog key
    /// （Apple 推荐的优雅降级写法：目录缺失该 key 时原样回退显示 key 本身，即中文原文，
    /// 不会出现裸标识符泄漏给用户）。
    ///
    /// 与 SwiftUI `Text(LocalizedStringKey)` 的关键区别：本方法不依赖 `.environment(\.locale)`
    /// 树形传播，而是每次调用时同步读取一次 `LanguagePreference.current`——适用于结果需要
    /// 以纯 `String`（而非 `Text`）形式跨上下文使用的场景（如作为另一段插值文本的参数、或
    /// 供非 View 类型消费）。
    static func localizedString(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: current.effectiveLocale)
    }

    /// 当前生效的语言偏好：同步读取 `UserDefaults.standard`（与 `LanguageSettingsView`/
    /// `MoodmentsApp` 的 `@AppStorage(storageKey)` 读写同一 key），缺省（从未设置）时为
    /// `.zhHans`（见类型头部说明）。
    static var current: LanguagePreference {
        guard let raw = UserDefaults.standard.string(forKey: storageKey) else { return .zhHans }
        return LanguagePreference(rawValue: raw) ?? .zhHans
    }

    /// 解析出的目标 `Locale`；`.system` 返回 `nil` 表示「不覆盖」（见阶段7计划决策4：
    /// 「跟随系统」不覆盖），调用方应回落到 `Locale.autoupdatingCurrent`（见 `effectiveLocale`）。
    var resolvedLocale: Locale? {
        switch self {
        case .zhHans: Locale(identifier: "zh-Hans")
        case .english: Locale(identifier: "en")
        case .system: nil
        }
    }

    /// 供 `.environment(\.locale, ...)` 与 `localizedString(_:)` 统一消费的最终生效 locale：
    /// `.system` 时用 `Locale.autoupdatingCurrent`（跟随系统变化），其余两态用显式覆盖值。
    var effectiveLocale: Locale {
        resolvedLocale ?? Locale.autoupdatingCurrent
    }

    /// 设置页语言选择行展示名（见 docs/current/implementation-truth.md §4.11、`LanguageSettingsView`）。
    var displayNameKey: LocalizedStringKey {
        switch self {
        case .zhHans: "简体中文"
        case .english: "English"
        case .system: "跟随系统"
        }
    }
}
