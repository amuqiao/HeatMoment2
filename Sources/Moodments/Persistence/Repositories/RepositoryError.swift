import Foundation

/// Repository 层的错误类型。按 `CLAUDE.md`「不擅自添加兜底策略」约定：
/// 对不存在的 id 进行更新/删除/恢复等操作时必须让错误快速暴露，禁止静默 no-op。
enum RepositoryError: Error, Equatable {
    case momentNotFound(UUID)
    case tagNotFound(UUID)
}
