import Foundation

/// Repository 层的错误类型。按 `CLAUDE.md`「不擅自添加兜底策略」约定：
/// 对不存在的 id 进行更新/删除/恢复等操作时必须让错误快速暴露，禁止静默 no-op。
enum RepositoryError: Error, Equatable {
    case momentNotFound(UUID)
    case tagNotFound(UUID)
    /// 图片 id 不存在（canonical asset metadata/link 中找不到对应业务图片）。
    case momentImageNotFound(UUID)
    case assetStoreUnavailable
    /// 重命名标签撞名；由 canonical repository 在单个事务内检查并快速失败。
    case tagNameConflict(String)
    /// 创建写入超过免费额度。UI/application service 可据此打开对应 Paywall，不静默创建。
    case quotaExceeded(QuotaKind)
}
