import Foundation

/// 免费 / Pro 限额常量——全 App 的唯一权威定义。
///
/// 数值来源：`docs/product-mental-model.md` §2「免费 / Pro 限额（唯一权威）」。
/// 记录流程、数据模型计数口径、订阅与 Paywall 触发均应引用本类型，不得在其他位置重复或另行定义限额数值。
enum Quota {
    /// 免费用户 Moment（日记）篇数上限：最多 15 篇。
    /// 计数口径：统计所有尚未物理删除的记录（含垃圾箱内 `isDeleted==true` 的），
    /// 软删除不释放配额（见 `docs/current/local-data-architecture.md` §3）。
    static let freeMomentLimit = 15

    /// 免费用户单篇 Moment 照片数上限：每篇最多 3 张（以 `images.count` 校验）。
    static let freePhotosPerMomentLimit = 3

    /// 免费用户标签数上限：最多 3 个（以 `Tag` 表总行数为准，标签无软删除概念）。
    static let freeTagLimit = 3
}
