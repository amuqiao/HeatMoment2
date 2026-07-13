import Foundation

/// 订阅状态本地缓存（见 `docs/current/local-data-architecture.md` §7）：**不接入 CloudKit**——
/// Apple 账号层面的 entitlement 已由 StoreKit 自身在同一 Apple ID 下跨设备生效，无需再造一份
/// CloudKit 同步、避免双重数据源。本缓存只用于 UI 快速展示（减少每次开屏的判断延迟），
/// 任何「是否放行」的最终判断都必须以当次 `Transaction.currentEntitlements` 查询结果为准
/// （docs/current/implementation-truth.md §11.4，见 `SubscriptionService.currentEntitlementIsPro()`）。
struct SubscriptionStateCache: Codable, Sendable, Equatable {
    /// = `subscriptionActive || lifetimeUnlocked`（OR 结果，见 docs/current/implementation-truth.md §11.1）。
    var isPro: Bool
    /// 月订阅当前有效。
    var subscriptionActive: Bool
    /// 终身买断已购（`[设计决策，超出原 App]`）。
    var lifetimeUnlocked: Bool
    var productID: String?
    /// 仅对月订阅有意义；终身买断为 `nil`。
    var expirationDate: Date?
    var originalTransactionID: String?
    var lastVerifiedAt: Date

    static let notPro = SubscriptionStateCache(
        isPro: false, subscriptionActive: false, lifetimeUnlocked: false,
        productID: nil, expirationDate: nil, originalTransactionID: nil, lastVerifiedAt: .distantPast
    )
}

/// `SubscriptionStateCache` 的 `UserDefaults` 持久化（Codable JSON blob，见 docs/current/local-data-architecture.md §7）。
///
/// **解码失败按「视为无缓存」处理，不额外暴露错误**：与 `AppearanceStore.load()` 对单个坏轴
/// 的自愈处理同一先例（阶段6 as-built）——本缓存被文档明确定义为「只加速展示、非权威依据」，
/// 且权威判定（`Transaction.currentEntitlements`）每次冷启动/回前台都会重新核对并覆盖本缓存
/// （docs/current/implementation-truth.md §11.4），坏缓存的正确恢复路径就是「当作没有缓存、以下一次现场重查结果为准」，
/// 不是需要用户感知的错误。
struct SubscriptionStateCacheStore {
    private static let key = "com.heatmoment.subscriptionStateCache"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> SubscriptionStateCache? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(SubscriptionStateCache.self, from: data)
    }

    func save(_ cache: SubscriptionStateCache) {
        guard let data = try? JSONEncoder().encode(cache) else {
            assertionFailure("SubscriptionStateCache 编码失败：\(cache)")
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}
