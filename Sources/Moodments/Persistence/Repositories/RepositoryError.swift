import Foundation

/// Repository 层的错误类型。按 `CLAUDE.md`「不擅自添加兜底策略」约定：
/// 对不存在的 id 进行更新/删除/恢复等操作时必须让错误快速暴露，禁止静默 no-op。
enum RepositoryError: Error, Equatable {
    case momentNotFound(UUID)
    case tagNotFound(UUID)
    /// `MomentImage.id` 不存在（见 `MomentRepository.imageData(imageID:)`，阶段 4）。
    case momentImageNotFound(UUID)
    /// 重命名标签撞名（见 `TagRepository.renameTag(id:newName:)`，阶段6：应用层查重，
    /// CloudKit 不支持 `.unique`，与 `createTag` 前置查重同一约束）。
    case tagNameConflict(String)
    /// 创建写入超过免费额度。UI/application service 可据此打开对应 Paywall，不静默创建。
    case quotaExceeded(QuotaKind)
}
