import Foundation

/// 组合式外观偏好：模式 × 主色 × 背景纹理（含精选子状态）× 图片展示（见 docs/current/implementation-truth.md §5.3、
/// docs/current/local-data-architecture.md §6）。复用既有偏好枚举，不新造别名类型。
struct AppearancePreference: Sendable, Equatable {
    var mode: ThemeMode
    var accentColor: AccentColorOption
    var backgroundTexture: BackgroundTexture
    var featuredBackground: FeaturedBackground
    var imageDisplayMode: ImageDisplayMode

    /// 产品默认值：暗色 + 紫罗兰 + 网格 + 滚动（见 docs/current/implementation-truth.md §5.3.1/§5.3.2/§5.3.3/§5.3.4）。
    static let `default` = AppearancePreference(
        mode: .dark,
        accentColor: .violet,
        backgroundTexture: .grid,
        featuredBackground: .default,
        imageDisplayMode: .scroll
    )

    init(
        mode: ThemeMode,
        accentColor: AccentColorOption,
        backgroundTexture: BackgroundTexture,
        featuredBackground: FeaturedBackground = .default,
        imageDisplayMode: ImageDisplayMode
    ) {
        self.mode = mode
        self.accentColor = accentColor
        self.backgroundTexture = backgroundTexture
        self.featuredBackground = featuredBackground
        self.imageDisplayMode = imageDisplayMode
    }
}

/// 外观偏好写入失败（见 docs/current/implementation-truth.md §5.3.7：主色/模式/纹理与照片显示是两条独立的失败反馈）。
enum AppearanceStoreError: Error, Equatable {
    case saveFailed
}

struct CustomBackgroundImageWriteTarget: Sendable, Equatable {
    let directoryURL: URL
    let fileURL: URL
    let simulateSaveFailure: Bool

    func save(_ data: Data) throws {
        guard !simulateSaveFailure else { throw AppearanceStoreError.saveFailed }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
    }

    func saveInBackground(_ data: Data) async throws {
        guard !simulateSaveFailure else { throw AppearanceStoreError.saveFailed }
        let directoryURL = directoryURL
        let fileURL = fileURL
        try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic])
        }.value
    }
}

/// `AppearancePreference` 的 UserDefaults 持久化：非资料库模型，避免把
/// 展示层偏好卷入 CloudKit 冲突解决范围；不跨设备同步，见 docs/plans/README.md #3）。
///
/// **逐轴持久化**：每个轴各自一个 UserDefaults key，而非编码成单一 blob——使坏配置能够
/// 「按轴回落默认值」并精确计数「已修正 N 项」（见 docs/current/implementation-truth.md §5.3.7），而不会因为其中一个字段
/// 损坏导致整份偏好一起报废。
struct AppearanceStore {
    private enum Key {
        static let mode = "com.heatmoment.appearance.mode"
        static let accentColor = "com.heatmoment.appearance.accentColor"
        static let backgroundTexture = "com.heatmoment.appearance.backgroundTexture"
        static let featuredBackground = "com.heatmoment.appearance.featuredBackground"
        static let imageDisplayMode = "com.heatmoment.appearance.imageDisplayMode"
    }

    private static let customBackgroundImageFileName = "custom-background.jpg"

    private let defaults: UserDefaults
    private let customBackgroundImageDirectoryURL: URL
    /// 仅供测试注入必失败场景（见 `UITestSupport` 的 `-uiTestFailAppearanceSave`，
    /// docs/current/implementation-truth.md §5.3.7 异常反馈验收），生产路径恒为 `false`。
    private let simulateSaveFailure: Bool

    init(
        defaults: UserDefaults = .standard,
        customBackgroundImageDirectoryURL: URL = Self.defaultCustomBackgroundImageDirectoryURL(),
        simulateSaveFailure: Bool = false
    ) {
        self.defaults = defaults
        self.customBackgroundImageDirectoryURL = customBackgroundImageDirectoryURL
        self.simulateSaveFailure = simulateSaveFailure
    }

    /// 写入完整偏好（各偏好字段一次性写入，读取仍按字段各自解析、互不影响）。
    /// - Throws: `AppearanceStoreError.saveFailed`（仅测试注入场景触发；生产 `UserDefaults`
    ///   写入本身不失败，UI 层据本方法的成功/失败结果决定是否展示保存失败提示，
    ///   不因失败回滚已经乐观更新的视觉状态，见 docs/current/implementation-truth.md §5.3.7）。
    func save(_ preference: AppearancePreference) throws {
        guard !simulateSaveFailure else { throw AppearanceStoreError.saveFailed }
        defaults.set(preference.mode.rawValue, forKey: Key.mode)
        defaults.set(preference.accentColor.rawValue, forKey: Key.accentColor)
        defaults.set(preference.backgroundTexture.rawValue, forKey: Key.backgroundTexture)
        defaults.set(preference.featuredBackground.rawValue, forKey: Key.featuredBackground)
        defaults.set(preference.imageDisplayMode.rawValue, forKey: Key.imageDisplayMode)
    }

    func saveCustomBackgroundImageData(_ data: Data) throws {
        try customBackgroundImageWriteTarget().save(data)
    }

    func saveCustomBackgroundImageDataInBackground(_ data: Data) async throws {
        try await customBackgroundImageWriteTarget().saveInBackground(data)
    }

    func loadCustomBackgroundImageData() throws -> Data? {
        guard FileManager.default.fileExists(atPath: customBackgroundImageFileURL.path) else {
            return nil
        }
        return try Data(contentsOf: customBackgroundImageFileURL)
    }

    /// 逐轴读取：缺失 key（如首次启动）直接用默认值，不计入「已修正」——那是正常的初始态，
    /// 不是坏配置；只有「key 存在但 rawValue 无法解析」才视为坏配置，**立即回写该轴默认值**
    /// （自愈，避免下次冷启动对同一份坏数据重复判定、重复计数、重复展示「已修正」提示）并计数
    /// （见 docs/current/implementation-truth.md §5.3.7「已修正 N 项本地偏好配置」）——`correctedCount` 如实反映**本次**修正数，
    /// 不受自愈回写影响（回写发生在计数之后，且只影响下一次 `load()` 的判定结果）。
    func load() -> (preference: AppearancePreference, correctedCount: Int) {
        var correctedCount = 0

        func resolve<T: RawRepresentable>(
            _ key: String,
            default defaultValue: T
        ) -> T where T.RawValue == String {
            guard let raw = defaults.string(forKey: key) else { return defaultValue }
            guard let resolved = T(rawValue: raw) else {
                correctedCount += 1
                defaults.set(defaultValue.rawValue, forKey: key)
                return defaultValue
            }
            return resolved
        }

        let preference = AppearancePreference(
            mode: resolve(Key.mode, default: AppearancePreference.default.mode),
            accentColor: resolve(
                Key.accentColor,
                default: AppearancePreference.default.accentColor
            ),
            backgroundTexture: resolve(
                Key.backgroundTexture, default: AppearancePreference.default.backgroundTexture
            ),
            featuredBackground: resolve(
                Key.featuredBackground,
                default: AppearancePreference.default.featuredBackground
            ),
            imageDisplayMode: resolve(
                Key.imageDisplayMode, default: AppearancePreference.default.imageDisplayMode
            )
        )
        return (preference, correctedCount)
    }

    var customBackgroundImageFileURL: URL {
        customBackgroundImageDirectoryURL.appendingPathComponent(Self.customBackgroundImageFileName)
    }

    func customBackgroundImageWriteTarget() -> CustomBackgroundImageWriteTarget {
        CustomBackgroundImageWriteTarget(
            directoryURL: customBackgroundImageDirectoryURL,
            fileURL: customBackgroundImageFileURL,
            simulateSaveFailure: simulateSaveFailure
        )
    }

    private static func defaultCustomBackgroundImageDirectoryURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return baseURL.appendingPathComponent("Appearance", isDirectory: true)
    }
}
