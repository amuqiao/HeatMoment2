import Foundation

/// 组合式外观偏好：模式 × 主色 × 背景纹理 × 图片展示（见 05-design-system.md §5.3、
/// 07-data-persistence.md §6）。复用既有 4 个枚举（`ThemeMode` / `AccentColorOption` /
/// `BackgroundTexture` / `ImageDisplayMode`），不新造别名类型。
struct AppearancePreference: Sendable, Equatable {
    var mode: ThemeMode
    var accentColor: AccentColorOption
    var backgroundTexture: BackgroundTexture
    var imageDisplayMode: ImageDisplayMode

    /// 产品默认值：暗色 + 紫罗兰 + 网格 + 滚动（见 05 §5.3.1/§5.3.2/§5.3.3/§5.3.4）。
    static let `default` = AppearancePreference(
        mode: .dark, accentColor: .violet, backgroundTexture: .grid, imageDisplayMode: .scroll
    )
}

/// 外观偏好写入失败（见 05 §5.3.7：主色/模式/纹理与照片显示是两条独立的失败反馈）。
enum AppearanceStoreError: Error, Equatable {
    case saveFailed
}

/// `AppearancePreference` 的 UserDefaults 持久化（见 07 §6：非 SwiftData `@Model`，避免把
/// 展示层偏好卷入 CloudKit 冲突解决范围；不跨设备同步，见 13-open-questions.md #3）。
///
/// **逐轴持久化**：每个轴各自一个 UserDefaults key，而非编码成单一 blob——使坏配置能够
/// 「按轴回落默认值」并精确计数「已修正 N 项」（见 05 §5.3.7），而不会因为其中一个字段
/// 损坏导致整份偏好一起报废。
struct AppearanceStore {
    private enum Key {
        static let mode = "com.moodments.appearance.mode"
        static let accentColor = "com.moodments.appearance.accentColor"
        static let backgroundTexture = "com.moodments.appearance.backgroundTexture"
        static let imageDisplayMode = "com.moodments.appearance.imageDisplayMode"
    }

    private let defaults: UserDefaults
    /// 仅供测试注入必失败场景（见 `UITestSupport` 的 `-uiTestFailAppearanceSave`，
    /// 05 §5.3.7 异常反馈验收），生产路径恒为 `false`。
    private let simulateSaveFailure: Bool

    init(defaults: UserDefaults = .standard, simulateSaveFailure: Bool = false) {
        self.defaults = defaults
        self.simulateSaveFailure = simulateSaveFailure
    }

    /// 写入完整偏好（四轴一次性写入，读取仍按轴各自解析、互不影响）。
    /// - Throws: `AppearanceStoreError.saveFailed`（仅测试注入场景触发；生产 `UserDefaults`
    ///   写入本身不失败，UI 层据本方法的成功/失败结果决定是否展示保存失败提示，
    ///   不因失败回滚已经乐观更新的视觉状态，见 05 §5.3.7）。
    func save(_ preference: AppearancePreference) throws {
        guard !simulateSaveFailure else { throw AppearanceStoreError.saveFailed }
        defaults.set(preference.mode.rawValue, forKey: Key.mode)
        defaults.set(preference.accentColor.rawValue, forKey: Key.accentColor)
        defaults.set(preference.backgroundTexture.rawValue, forKey: Key.backgroundTexture)
        defaults.set(preference.imageDisplayMode.rawValue, forKey: Key.imageDisplayMode)
    }

    /// 逐轴读取：缺失 key（如首次启动）直接用默认值，不计入「已修正」——那是正常的初始态，
    /// 不是坏配置；只有「key 存在但 rawValue 无法解析」才视为坏配置，回落默认值并计数
    /// （见 05 §5.3.7「已修正 N 项本地偏好配置」）。
    func load() -> (preference: AppearancePreference, correctedCount: Int) {
        var correctedCount = 0

        func resolve<T: RawRepresentable>(_ key: String, default defaultValue: T) -> T where T.RawValue == String {
            guard let raw = defaults.string(forKey: key) else { return defaultValue }
            guard let resolved = T(rawValue: raw) else {
                correctedCount += 1
                return defaultValue
            }
            return resolved
        }

        let preference = AppearancePreference(
            mode: resolve(Key.mode, default: AppearancePreference.default.mode),
            accentColor: resolve(Key.accentColor, default: AppearancePreference.default.accentColor),
            backgroundTexture: resolve(
                Key.backgroundTexture, default: AppearancePreference.default.backgroundTexture
            ),
            imageDisplayMode: resolve(
                Key.imageDisplayMode, default: AppearancePreference.default.imageDisplayMode
            )
        )
        return (preference, correctedCount)
    }
}
