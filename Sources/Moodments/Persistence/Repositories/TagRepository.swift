import Foundation
import SwiftData

/// `Tag` 的只读快照，供跨隔离域传递（不传 `@Model` 引用）。
struct TagSnapshot: Sendable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let createdAt: Date

    init(_ tag: Tag) {
        id = tag.id
        name = tag.name
        createdAt = tag.createdAt
    }
}

struct TagCreateOrReuseResult: Sendable, Equatable {
    let id: UUID
    let name: String
    let didCreate: Bool
}

/// `Tag` 的后台写入仓库（`ModelActor`）：应用层查重、增删、额度计数。
/// 唯一性由应用层保存前查重保证（CloudKit 不支持 `.unique`，见 `docs/design/07-data-persistence.md` §2）。
@ModelActor
actor TagRepository {
    /// 应用层查重：按名称查找是否已存在同名标签。
    func findTag(named name: String) throws -> TagSnapshot? {
        var descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.name == name })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(TagSnapshot.init)
    }

    /// 新建标签，返回其 id。调用方应先用 `findTag(named:)` 查重。
    @discardableResult
    func createTag(name: String) throws -> UUID {
        let tag = Tag(name: name)
        modelContext.insert(tag)
        try modelContext.save()
        return tag.id
    }

    /// 原子地完成“同名复用 + 额度终判 + 创建”。该方法刻意留在同一个 `ModelActor`
    /// 临界区内，避免 UI/service 层跨多次 `await` 拆开后并发创建重复标签或绕过额度。
    func createOrReuseTag(
        name: String,
        quotaService: QuotaService
    ) throws -> TagCreateOrReuseResult {
        if let existing = try findTag(named: name) {
            return TagCreateOrReuseResult(
                id: existing.id,
                name: existing.name,
                didCreate: false
            )
        }
        switch quotaService.checkCanCreateTag(currentTagCount: try totalTagCount()) {
        case .allowed:
            break
        case .exceeded(let kind):
            throw RepositoryError.quotaExceeded(kind)
        }
        let tag = Tag(name: name)
        modelContext.insert(tag)
        try modelContext.save()
        return TagCreateOrReuseResult(
            id: tag.id,
            name: tag.name,
            didCreate: true
        )
    }

    /// 重命名标签（见 04-screen-specs.md §4.13：`TagManageView` 列表项点击进入重命名）：
    /// 应用层查重（与 `createTag` 前置查重同一约束，CloudKit 不支持 `.unique`）——若已存在
    /// 「另一个」同名标签（`existing.id != id`，重命名为自身原名不算冲突）则抛
    /// `RepositoryError.tagNameConflict`；`id` 不存在抛 `RepositoryError.tagNotFound`
    /// （不静默 no-op，见 CLAUDE.md「不擅自添加兜底策略」）。
    func renameTag(id: UUID, newName: String) throws {
        guard let tag = try fetchModel(id: id) else { throw RepositoryError.tagNotFound(id) }
        if let existing = try findTag(named: newName), existing.id != id {
            throw RepositoryError.tagNameConflict(newName)
        }
        tag.name = newName
        try modelContext.save()
    }

    /// 删除标签：仅解除其与时刻的关联（`.nullify`），不影响任何 `Moment` 的内容或
    /// `isDeleted` 状态（标签删除与 Moment 软删除生命周期完全独立，见 07 §4）。
    /// - Throws: `RepositoryError.tagNotFound` 若 `id` 不存在（不静默 no-op）。
    func deleteTag(id: UUID) throws {
        guard let tag = try fetchModel(id: id) else { throw RepositoryError.tagNotFound(id) }
        modelContext.delete(tag)
        try modelContext.save()
    }

    /// 标签列表（管理区展示用），按创建时间升序。
    func fetchAll() throws -> [TagSnapshot] {
        let descriptor = FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map(TagSnapshot.init)
    }

    /// 免费额度计数：`Tag` 表总行数（标签无软删除概念，删除即物理删除）。
    func totalTagCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<Tag>())
    }

    private func fetchModel(id: UUID) throws -> Tag? {
        var descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
