import Foundation

/// `EntitlementProviding` 的 StoreKit 适配（见阶段7计划决策1、`docs/current/implementation-truth.md` §11.4）。
///
/// **不持有 `SubscriptionService` 引用**：后者是 `@MainActor @Observable` 类型，不满足
/// `Sendable`、也不应跨隔离域传递；本类型只是把「已经现场重查过一次」的快照 `isPro` 值
/// 适配成 `QuotaService` 需要的 `EntitlementProviding` 协议形状。调用方必须先
/// `await subscriptionService.currentEntitlementIsPro()` 拿到当次权威结果，再用该结果构造
/// 本类型——**限额判定唯一落点仍是 `QuotaService`**（见 `docs/current/implementation-truth.md` §6），
/// 本类型不参与判定逻辑本身，只做值的搬运。
struct SubscriptionEntitlementProvider: EntitlementProviding {
    let isPro: Bool
}
