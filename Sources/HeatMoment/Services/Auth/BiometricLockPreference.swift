import Foundation

/// 「面容解锁」开关的本地持久化（见 `docs/current/implementation-truth.md` §10.1.2）：
/// **设备级本地偏好**，存 `UserDefaults`（非敏感信息，评估为不需要 Keychain 的过度设计），
/// **不参与 iCloud 同步**（同一账号下不同设备可能希望不同的锁定策略，如 iPad 常驻家中可不锁）。
/// 默认关闭（截图为关闭态，见 docs/current/implementation-truth.md §10.1.2）。
enum BiometricLockPreference {
    private static let key = "com.heatmoment.privacyLock.enabled"

    /// - Returns: 当前是否开启隐私锁。DEBUG 下若带
    ///   `-uiTestForcePrivacyLockEnabled` 启动参数，恒返回 `true`（供 `PrivacyLockUITests` 在
    ///   不依赖设置页开关交互的前提下验证锁生命周期时序，见 `UITestSupport`）。
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        #if DEBUG
        if UITestSupport.wantsForcePrivacyLockEnabled { return true }
        #endif
        return defaults.bool(forKey: key)
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: key)
    }
}
