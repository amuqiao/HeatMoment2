import Foundation

/// Pro 权益判定的注入点。阶段 1 只提供默认非 Pro 的实现；
/// 真正基于 StoreKit 2 的判定在阶段 7 由 `SubscriptionService` 实现并注入（见 08-architecture.md §6）。
protocol EntitlementProviding: Sendable {
    var isPro: Bool { get }
}

/// 阶段 1 默认实现：始终非 Pro，供本地开发与单元测试注入。
struct DefaultEntitlementProvider: EntitlementProviding {
    var isPro: Bool { false }
}

/// 触发限额校验的额度维度。
enum QuotaKind: Sendable, Equatable {
    /// Moment（日记）篇数：免费最多 `Quota.freeMomentLimit` 篇。
    case moments
    /// 单篇照片数：免费每篇最多 `Quota.freePhotosPerMomentLimit` 张。
    case photosPerMoment
    /// 标签数：免费最多 `Quota.freeTagLimit` 个。
    case tags
}

/// 限额校验结果。UI 只消费该结果、不自行判断额度（见 08-architecture.md §6）。
enum QuotaCheck: Sendable, Equatable {
    case allowed
    case exceeded(QuotaKind)
}

/// 免费额度 + Pro 判定校验（唯一权威落点）。
/// 限额数值唯一权威见 `Models/Quota.swift`（引用 `06-domain-model.md` §2），本类型只做比较，不重复定义数值。
struct QuotaService: Sendable {
    private let entitlementProvider: EntitlementProviding

    init(entitlementProvider: EntitlementProviding = DefaultEntitlementProvider()) {
        self.entitlementProvider = entitlementProvider
    }

    /// 校验能否再新增一篇 Moment。`currentMomentCount` 须按额度计数口径传入
    /// （含垃圾箱内软删除记录，见 canonical repository 的额度计数口径）。
    func checkCanCreateMoment(currentMomentCount: Int) -> QuotaCheck {
        guard !entitlementProvider.isPro else { return .allowed }
        return currentMomentCount < Quota.freeMomentLimit ? .allowed : .exceeded(.moments)
    }

    /// 校验能否为某篇 Moment 再新增一张照片。
    func checkCanAddPhoto(currentPhotoCount: Int) -> QuotaCheck {
        guard !entitlementProvider.isPro else { return .allowed }
        return currentPhotoCount < Quota.freePhotosPerMomentLimit
            ? .allowed : .exceeded(.photosPerMoment)
    }

    /// 校验能否再新增一个标签。
    func checkCanCreateTag(currentTagCount: Int) -> QuotaCheck {
        guard !entitlementProvider.isPro else { return .allowed }
        return currentTagCount < Quota.freeTagLimit ? .allowed : .exceeded(.tags)
    }

    /// 还可再添加的照片数（Pro 不限，返回 `Int.max`）：供选择器上限等 UI 派生使用，
    /// 判定权威仍是 `checkCanAddPhoto`。集中在此以免 View 直接用 `Quota` 常量做减法、
    /// 且对 `isPro` 无感知（见 08-architecture.md §6）。
    func remainingPhotoSlots(currentPhotoCount: Int) -> Int {
        guard !entitlementProvider.isPro else { return .max }
        return max(0, Quota.freePhotosPerMomentLimit - currentPhotoCount)
    }
}
