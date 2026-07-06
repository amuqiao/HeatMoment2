import Foundation
import Observation
import SwiftData

/// 一张待保存的草稿照片：已压缩为 JPEG `Data`（见 `ImageCompressor`）。缩略图直接由
/// `jpegData` 现场解码渲染——草稿态最多 `Quota.freePhotosPerMomentLimit` 张，量小，无需
/// 额外磁盘缓存；持久化后时间轴/预览的缩略图缓存见 `ThumbnailCache`。
struct DraftPhoto: Identifiable, Equatable, Sendable {
    let id: UUID
    let jpegData: Data

    init(id: UUID = UUID(), jpegData: Data) {
        self.id = id
        self.jpegData = jpegData
    }
}

/// `isDirty` 比较用的字段快照（不含 `id`，只比较可编辑内容）。
private struct EditorSnapshot: Equatable {
    let mood: Mood
    let title: String
    let bodyText: String
    let occurredAt: Date
    let tagIDs: [UUID]
    let photos: [DraftPhoto]
}

/// 编辑器草稿的唯一持有者（见 `docs/plans/implementation-plan.md` 阶段 3、
/// `docs/design/04-screen-specs.md` §4.4、`docs/design/03-user-flows.md` §3.1）。
///
/// 持有情绪/标题/正文/发生时间/已选标签/草稿照片等全部可编辑字段：
/// - `.create` 默认发生时间为 `.now`、情绪取「上次选择」（否则回退 `.normal`，由调用方经
///   `lastUsedMood` 注入，持久化机制见 `MomentEditorView` 的 `@AppStorage` 用法）；
/// - `.edit(id)` 经 `load()` 从仓库异步载入既有数据，载入完成前 `isLoaded == false`。
///
/// 限额判定只消费 `QuotaService` 结果（见 `docs/design/08-architecture.md` §6），本类型不
/// 重复定义限额数值；照片额度校验直接用 `draftPhotos.count`（草稿即完整当前状态，编辑态
/// 载入的既有照片也计入其中，无需另外查仓库）。
@MainActor
@Observable
final class MomentEditorModel {
    let mode: EditorMode

    private let repository: MomentRepository
    private let tagRepository: TagRepository
    private let quotaService: QuotaService

    /// 编辑态是否已完成从仓库载入；新建态恒为 `true`（无需等待异步载入）。
    private(set) var isLoaded: Bool

    var mood: Mood
    var title: String = ""
    var bodyText: String = ""
    var occurredAt: Date
    var selectedTagIDs: [UUID] = []
    var tagNamesByID: [UUID: String] = [:]
    var draftPhotos: [DraftPhoto] = []

    /// 打开时的字段快照，供 `isDirty` 比较（见 03-user-flows.md §3.1：取消若脏需二次确认）。
    private var baseline: EditorSnapshot

    init(
        mode: EditorMode,
        modelContainer: ModelContainer,
        quotaService: QuotaService = QuotaService(),
        lastUsedMood: Mood = .normal
    ) {
        self.mode = mode
        self.repository = MomentRepository(modelContainer: modelContainer)
        self.tagRepository = TagRepository(modelContainer: modelContainer)
        self.quotaService = quotaService

        // 用局部变量而非 `self.mood`/`self.occurredAt` 组装 baseline：`@Observable` 宏生成的
        // 存储属性访问要求 `self` 已完全初始化，在此处（其余存储属性尚未全部赋值）直接读取
        // 会被编译器拒绝，故先用局部变量算好两份要用的值，再各自赋给对应的 `self` 属性。
        let initialMood: Mood
        let initialOccurredAt = Date.now
        let initialIsLoaded: Bool
        switch mode {
        case .create:
            initialMood = lastUsedMood
            initialIsLoaded = true
        case .edit:
            // 载入完成前的占位值，`load()` 会覆盖；期间 `isLoaded == false`，View 展示加载态。
            initialMood = .normal
            initialIsLoaded = false
        }
        self.mood = initialMood
        self.occurredAt = initialOccurredAt
        self.isLoaded = initialIsLoaded
        self.baseline = EditorSnapshot(
            mood: initialMood, title: "", bodyText: "", occurredAt: initialOccurredAt, tagIDs: [], photos: []
        )
    }

    /// 编辑态从仓库载入既有数据；新建态直接返回（幂等，调用方无需先判断 `mode`）。
    /// - Throws: `RepositoryError.momentNotFound` 若 `id` 已不存在（如被彻底删除后仍打开编辑）。
    func load() async throws {
        guard case let .edit(id) = mode else { return }
        let payload = try await repository.editingPayload(id: id)
        mood = payload.snapshot.mood
        title = payload.snapshot.title
        bodyText = payload.snapshot.bodyText
        occurredAt = payload.snapshot.occurredAt
        selectedTagIDs = payload.snapshot.tagIDs
        tagNamesByID = payload.tagNames
        draftPhotos = payload.imageDatas.map { DraftPhoto(jpegData: $0) }
        baseline = currentSnapshot
        isLoaded = true
    }

    /// 标题/正文/照片至少一项非空才可保存（见 03-user-flows.md §3.1）。
    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draftPhotos.isEmpty
    }

    /// 相对打开时的快照是否有未保存改动（取消时据此决定是否需要二次确认）。
    var isDirty: Bool { currentSnapshot != baseline }

    private var currentSnapshot: EditorSnapshot {
        EditorSnapshot(
            mood: mood, title: title, bodyText: bodyText, occurredAt: occurredAt,
            tagIDs: selectedTagIDs, photos: draftPhotos
        )
    }

    // MARK: - 标签（见 04-screen-specs.md §4.6/§4.7）

    /// 标签就近浮窗内点选：已选则取消，未选则加入（多选，点选不关闭浮窗）。
    func toggleTagSelection(_ tag: TagSnapshot) {
        if let index = selectedTagIDs.firstIndex(of: tag.id) {
            selectedTagIDs.remove(at: index)
            tagNamesByID.removeValue(forKey: tag.id)
        } else {
            selectedTagIDs.append(tag.id)
            tagNamesByID[tag.id] = tag.name
        }
    }

    /// `TagCreateSheetView` 新建/复用完成后回填选中（若已选中则不重复添加）。
    func applyCreatedTag(id: UUID, name: String) {
        if !selectedTagIDs.contains(id) {
            selectedTagIDs.append(id)
        }
        tagNamesByID[id] = name
    }

    /// 标签「+添加」的前置额度校验（见 03-user-flows.md §3.1）：UI 只消费结果——允许则打开
    /// `TagCreateSheetView`，超额则改为打开 Paywall（`.quotaTag`）。
    func requestCreateTag() async throws -> QuotaCheck {
        let count = try await tagRepository.totalTagCount()
        return quotaService.checkCanCreateTag(currentTagCount: count)
    }

    // MARK: - 照片（见 04-screen-specs.md §4.4，压缩管线见 `ImageCompressor`）

    /// 追加一张已压缩的照片；额度校验用当前草稿照片数（草稿即完整当前状态，见类型头部）。
    @discardableResult
    func addPhoto(_ jpegData: Data) -> QuotaCheck {
        let check = quotaService.checkCanAddPhoto(currentPhotoCount: draftPhotos.count)
        if case .allowed = check {
            draftPhotos.append(DraftPhoto(jpegData: jpegData))
        }
        return check
    }

    func removePhoto(id: UUID) {
        draftPhotos.removeAll { $0.id == id }
    }

    // MARK: - 保存

    /// 组装当前草稿并写入仓库。`.edit` 态始终传入 `imageDatas`（即便照片未改动也按当前顺序
    /// 重建）——仓库层无法区分「未改动」与「改动为同样内容」，重建代价对最多 3 张照片可接受
    /// （见阶段 3 计划决策2）。
    /// - Throws: 仓库写入失败时抛出（如 `.edit` 态 id 已不存在），调用方不吞错。
    func save() async throws {
        let tagIDs = selectedTagIDs
        let photoDatas = draftPhotos.map(\.jpegData)
        switch mode {
        case .create:
            try await repository.createMoment(
                title: title, bodyText: bodyText, occurredAt: occurredAt, mood: mood,
                tagIDs: tagIDs, imageDatas: photoDatas
            )
        case let .edit(id):
            try await repository.updateMoment(
                id: id, title: title, bodyText: bodyText, occurredAt: occurredAt, mood: mood,
                tagIDs: tagIDs, imageDatas: photoDatas
            )
        }
    }
}
