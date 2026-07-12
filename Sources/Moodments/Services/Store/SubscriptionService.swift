import Foundation
import Observation
import StoreKit
import UIKit
import os

/// 购买结果，供 `ProPaywallView` 决定如何反馈（见 `docs/current/implementation-truth.md` §11.2）。
enum PurchaseOutcome: Sendable, Equatable {
    case success
    case userCancelled
    case pending
}

/// `SubscriptionService` 自身的错误。
enum SubscriptionServiceError: Error, Equatable {
    /// 购买回调返回了未通过 StoreKit 签名校验的 `Transaction`（不吞错，原样上抛）。
    case unverifiedTransaction
}

/// StoreKit 2 订阅/买断集成（见 `docs/current/implementation-truth.md`）：商品加载、购买、恢复购买、
/// 核销码入口、entitlement 核对与本地缓存刷新。
///
/// **并发边界**（见 `docs/current/implementation-truth.md` §5、阶段7计划必守约束）：本类型 `@MainActor`
/// （UI 消费的 `isPro`/`monthlyProduct`/`lifetimeProduct` 等状态在主线程更新）；`Transaction.updates`
/// 是非隔离的 `AsyncSequence`，用 `Task.detached` 接收，处理完成后 `await` 跳回 `@MainActor` 写状态。
///
/// **状态一致性**（docs/current/implementation-truth.md §11.4）：`isPro` 只是「当次查询完成后缓存下来的快照」，供 UI 快速展示
/// （如设置页 Pro 横幅、Paywall 是否显示「已是会员」）；**任何「是否放行某操作」的判断都必须
/// 调用 `currentEntitlementIsPro()` 现场重查**，不得直接读 `isPro` 做放行依据——三处额度闸门
/// （`TimelineHomeView`/`MomentEditorModel`）均遵循该约束（见阶段7计划决策1）。
@MainActor
@Observable
final class SubscriptionService {
    private(set) var isPro: Bool
    private(set) var monthlyProduct: Product?
    private(set) var lifetimeProduct: Product?

    private let cacheStore: SubscriptionStateCacheStore
    /// `nonisolated(unsafe)`：仅供 `deinit`（非隔离上下文，不能 `await` 跳回 `@MainActor`）
    /// 取消长任务；`Task.cancel()` 本身是线程安全操作，其余读写均发生在 `@MainActor` 方法内
    /// （`startObservingTransactionUpdates()`），不存在真正的并发写入竞争。
    private nonisolated(unsafe) var updatesTask: Task<Void, Never>?

    private static let logger = Logger(subsystem: "com.moodments.app", category: "SubscriptionService")

    init(cacheStore: SubscriptionStateCacheStore = SubscriptionStateCacheStore()) {
        self.cacheStore = cacheStore
        // 冷启动前先用本地缓存值展示（避免首帧无值/都判非 Pro 造成横幅短暂闪烁），
        // 权威判定仍会在 `refreshEntitlements()` 中现场重查并覆盖（见 docs/current/implementation-truth.md §11.4）。
        self.isPro = cacheStore.load()?.isPro ?? false
    }

    deinit {
        updatesTask?.cancel()
    }

    /// 启动时开长任务监听 `Transaction.updates`（见 docs/current/implementation-truth.md §11.1）：实时接收续订/退款/取消/兑换码
    /// 等异步事件。`Task.detached` 内不持有 `self` 的强引用（`[weak self]`），处理时
    /// `await self?.handle(...)` 跳回 `@MainActor`；多次调用幂等（已在监听则不重复开任务）。
    func startObservingTransactionUpdates() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(updateResult: update)
            }
        }
    }

    private func handle(updateResult: VerificationResult<Transaction>) async {
        guard case let .verified(transaction) = updateResult else {
            Self.logger.error("收到未通过签名校验的 Transaction.updates 事件，忽略")
            return
        }
        await transaction.finish()
        await refreshEntitlements()
    }

    /// 权威判定（docs/current/implementation-truth.md §11.4）：现场重查 `Transaction.currentEntitlements`，命中「月订阅未过期」
    /// 或「终身买断已购」任一即 Pro（OR 关系，见 docs/current/implementation-truth.md §11.1）。副作用：刷新本地缓存与 `isPro`
    /// （供 UI 展示），但**调用方判断是否放行某操作时必须使用本方法的返回值**，不得依赖副作用
    /// 写入后的 `isPro` 时序（同一次判定应只有一个真相来源）。
    @discardableResult
    func currentEntitlementIsPro() async -> Bool {
        var subscriptionActive = false
        var lifetimeUnlocked = false
        var expirationDate: Date?
        var productID: String?
        var originalTransactionID: String?

        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }
            switch transaction.productID {
            case StoreProductID.monthly:
                subscriptionActive = true
                expirationDate = transaction.expirationDate
                productID = transaction.productID
                originalTransactionID = String(transaction.originalID)
            case StoreProductID.lifetime:
                lifetimeUnlocked = true
                productID = transaction.productID
                originalTransactionID = String(transaction.originalID)
            default:
                continue
            }
        }

        let resolvedIsPro = subscriptionActive || lifetimeUnlocked
        cacheStore.save(SubscriptionStateCache(
            isPro: resolvedIsPro,
            subscriptionActive: subscriptionActive,
            lifetimeUnlocked: lifetimeUnlocked,
            productID: productID,
            expirationDate: expirationDate,
            originalTransactionID: originalTransactionID,
            lastVerifiedAt: .now
        ))
        isPro = resolvedIsPro
        return resolvedIsPro
    }

    /// 启动 / 回前台调用（见 docs/current/implementation-truth.md §11.1）：语义上等价 `currentEntitlementIsPro()`，只是标注调用
    /// 时机，供 `MoodmentsApp` 复用。
    func refreshEntitlements() async {
        _ = await currentEntitlementIsPro()
    }

    /// 加载商品信息（`ProPaywallView` 展示 `Product.displayPrice` 动态渲染用，见 docs/current/implementation-truth.md §11.1）。
    /// - Throws: `Product.products(for:)` 底层网络/StoreKit 错误原样上抛，不吞错。
    func loadProducts() async throws {
        let products = try await Product.products(for: StoreProductID.all)
        monthlyProduct = products.first { $0.id == StoreProductID.monthly }
        lifetimeProduct = products.first { $0.id == StoreProductID.lifetime }
    }

    /// 购买（见 docs/current/implementation-truth.md §11.2）：`.success` 校验签名后 `finish()` + 现场重查刷新；`.userCancelled`/
    /// `.pending` 不视为失败，调用方据返回枚举决定 UI 反馈。
    /// - Throws: `SubscriptionServiceError.unverifiedTransaction` 若签名校验失败；
    ///   `product.purchase()` 底层错误原样上抛，不吞错。
    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        let result = try await product.purchase()
        switch result {
        case let .success(verification):
            guard case let .verified(transaction) = verification else {
                throw SubscriptionServiceError.unverifiedTransaction
            }
            await transaction.finish()
            _ = await currentEntitlementIsPro()
            return .success
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
    }

    /// 恢复购买（见 docs/current/implementation-truth.md §11.2）：`AppStore.sync()` 后重新核对，返回是否命中任一有效 Pro 授权，
    /// 供 UI 即时反馈成功/未找到记录。
    /// - Throws: `AppStore.sync()` 底层错误原样上抛，不吞错。
    func restorePurchases() async throws -> Bool {
        try await AppStore.sync()
        return await currentEntitlementIsPro()
    }

    /// 是否可展示核销码入口（见 docs/current/implementation-truth.md §11.2：仅 iOS 平台且 `canMakePayments` 为真时展示）。
    static var canMakePayments: Bool { AppStore.canMakePayments }

    /// 唤起系统兑换码弹层（见 docs/current/implementation-truth.md §11.2）：兑换成功依赖 `Transaction.updates` 被动接收新授权，
    /// 本方法不轮询。
    /// - Throws: 底层弹层呈现失败原样上抛，不吞错。
    func presentCodeRedemption(in scene: UIWindowScene) async throws {
        try await AppStore.presentOfferCodeRedeemSheet(in: scene)
    }
}
