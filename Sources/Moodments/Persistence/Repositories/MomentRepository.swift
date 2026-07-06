import Foundation
import SwiftData

/// `Moment` 的只读快照，供跨隔离域传递（不传 `@Model` 引用，见 `docs/design/08-architecture.md` §5）。
struct MomentSnapshot: Sendable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let bodyText: String
    let occurredAt: Date
    let createdAt: Date
    let updatedAt: Date
    let mood: Mood
    let tagIDs: [UUID]
    let imageIDs: [UUID]
    let isDeleted: Bool
    let deletedAt: Date?

    init(_ moment: Moment) {
        id = moment.id
        title = moment.title
        bodyText = moment.bodyText
        occurredAt = moment.occurredAt
        createdAt = moment.createdAt
        updatedAt = moment.updatedAt
        mood = moment.mood
        tagIDs = moment.tags.map(\.id)
        // 按 sortIndex 排序：imageIDs 顺序即横向缩略图排列顺序（见 07-data-persistence.md §5）。
        imageIDs = moment.images.sorted { $0.sortIndex < $1.sortIndex }.map(\.id)
        isDeleted = moment.isDeleted
        deletedAt = moment.deletedAt
    }
}

/// 编辑态载入所需的完整数据（见阶段 3 计划：`MomentEditorModel.load()` 消费本类型）。
/// `tagNames` 供标签行回填文案；`imageDatas` 按 `sortIndex` 有序，即草稿照片的初始顺序。
struct MomentEditingPayload: Sendable, Equatable {
    let snapshot: MomentSnapshot
    let tagNames: [UUID: String]
    let imageDatas: [Data]
}

/// `Moment` 的后台写入仓库（`ModelActor`）：增删改、软删除生命周期、分页取数、额度计数。
/// 见 `docs/design/08-architecture.md` §6：Repository 层是业务规则唯一落点，写入在后台执行；
/// 额度计数与列表展示是两个不同查询，不得混用同一 `FetchDescriptor`（见 07-data-persistence.md §3）。
@ModelActor
actor MomentRepository {
    /// 新建一条时刻，返回其 id。
    @discardableResult
    func createMoment(
        title: String,
        bodyText: String,
        occurredAt: Date,
        mood: Mood,
        tagIDs: [UUID] = [],
        imageDatas: [Data] = []
    ) throws -> UUID {
        let moment = Moment(title: title, bodyText: bodyText, occurredAt: occurredAt, mood: mood)
        if !tagIDs.isEmpty {
            moment.tags = try fetchTags(ids: tagIDs)
        }
        for (index, data) in imageDatas.enumerated() {
            let image = MomentImage(sortIndex: index, imageData: data, moment: moment)
            moment.images.append(image)
            modelContext.insert(image)
        }
        modelContext.insert(moment)
        try modelContext.save()
        return moment.id
    }

    /// 更新一条时刻的字段；未传入的字段保持不变。`nil` 表示「不改」。
    /// `imageDatas` 非 `nil` 时，级联删除该 Moment 现有的全部 `MomentImage`，再按传入顺序
    /// 重建（`sortIndex` = 数组下标），供编辑态照片增删/重排使用（见阶段 3 计划）；
    /// 传 `nil` 表示本次调用不涉及照片改动，保持既有照片不变。
    /// - Throws: `RepositoryError.momentNotFound` 若 `id` 不存在（不静默 no-op）。
    func updateMoment(
        id: UUID,
        title: String? = nil,
        bodyText: String? = nil,
        occurredAt: Date? = nil,
        mood: Mood? = nil,
        tagIDs: [UUID]? = nil,
        imageDatas: [Data]? = nil
    ) throws {
        guard let moment = try fetchModel(id: id) else { throw RepositoryError.momentNotFound(id) }
        if let title { moment.title = title }
        if let bodyText { moment.bodyText = bodyText }
        if let occurredAt { moment.occurredAt = occurredAt }
        if let mood { moment.mood = mood }
        if let tagIDs { moment.tags = try fetchTags(ids: tagIDs) }
        if let imageDatas {
            for image in moment.images {
                modelContext.delete(image)
            }
            moment.images = []
            for (index, data) in imageDatas.enumerated() {
                let image = MomentImage(sortIndex: index, imageData: data, moment: moment)
                moment.images.append(image)
                modelContext.insert(image)
            }
        }
        moment.updatedAt = .now
        try modelContext.save()
    }

    /// 编辑态载入：返回快照 + 已选标签名（回填标签行文案）+ 按 `sortIndex` 有序的原图 `Data`
    /// （供 `MomentEditorModel.load()` 使用，见阶段 3 计划）。
    /// - Throws: `RepositoryError.momentNotFound` 若 `id` 不存在（不静默返回 `nil`，
    ///   与本仓库其余按 id 操作的方法一致，见 CLAUDE.md「不擅自添加兜底策略」）。
    func editingPayload(id: UUID) throws -> MomentEditingPayload {
        guard let moment = try fetchModel(id: id) else { throw RepositoryError.momentNotFound(id) }
        let snapshot = MomentSnapshot(moment)
        var tagNames: [UUID: String] = [:]
        for tag in moment.tags {
            tagNames[tag.id] = tag.name
        }
        let imageDatas = moment.images.sorted { $0.sortIndex < $1.sortIndex }.map(\.imageData)
        return MomentEditingPayload(snapshot: snapshot, tagNames: tagNames, imageDatas: imageDatas)
    }

    /// 软删除：移出主时间轴、进入垃圾箱，仍可恢复；不释放额度（见公理「删除是生命周期」）。
    /// - Throws: `RepositoryError.momentNotFound` 若 `id` 不存在。
    func softDelete(id: UUID) throws {
        guard let moment = try fetchModel(id: id) else { throw RepositoryError.momentNotFound(id) }
        moment.isDeleted = true
        moment.deletedAt = .now
        try modelContext.save()
    }

    /// 恢复：重新属于主时间轴，带着原发生时间/心情/标签/内容回归。
    /// - Throws: `RepositoryError.momentNotFound` 若 `id` 不存在。
    func restore(id: UUID) throws {
        guard let moment = try fetchModel(id: id) else { throw RepositoryError.momentNotFound(id) }
        moment.isDeleted = false
        moment.deletedAt = nil
        try modelContext.save()
    }

    /// 彻底删除：不可逆终态，物理移除（级联移除其 `images`，标签关系按 `.nullify` 解除）。
    /// - Throws: `RepositoryError.momentNotFound` 若 `id` 不存在。
    func purge(id: UUID) throws {
        guard let moment = try fetchModel(id: id) else { throw RepositoryError.momentNotFound(id) }
        modelContext.delete(moment)
        try modelContext.save()
    }

    /// 时间轴列表口径：按 `occurredAt` 倒序分页取**未软删除**的时刻。
    /// 注：`#Predicate` 须直接引用存储属性 `deletedFlag`（而非计算属性 `isDeleted`），
    /// 原因见 `Moment.deletedFlag` 上的注释（SwiftData 对 `is` 前缀 Bool 属性的已知问题）。
    func fetchPage(offset: Int, limit: Int) throws -> [MomentSnapshot] {
        var descriptor = FetchDescriptor<Moment>(
            predicate: #Predicate { $0.deletedFlag == false },
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(MomentSnapshot.init)
    }

    /// 垃圾箱列表：按 `occurredAt` 倒序取**已软删除**的时刻。
    func fetchTrash() throws -> [MomentSnapshot] {
        let descriptor = FetchDescriptor<Moment>(
            predicate: #Predicate { $0.deletedFlag == true },
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(MomentSnapshot.init)
    }

    /// 免费额度计数口径：统计**所有尚未物理删除的记录（含垃圾箱内 `isDeleted==true` 的）**，
    /// 与 `fetchPage` 的列表展示查询分离，不得混用（见 06-domain-model.md §2、07 §3）。
    func totalMomentCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<Moment>())
    }

    /// 单篇时刻的照片数（额度校验用，以 `images.count` 校验）。
    func imageCount(momentID: UUID) throws -> Int {
        try fetchModel(id: momentID)?.images.count ?? 0
    }

    private func fetchModel(id: UUID) throws -> Moment? {
        var descriptor = FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchTags(ids: [UUID]) throws -> [Tag] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Tag>(predicate: #Predicate { ids.contains($0.id) })
        return try modelContext.fetch(descriptor)
    }
}
