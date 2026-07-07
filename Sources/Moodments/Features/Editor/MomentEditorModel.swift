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
///
/// **Pro 放行判定**（见阶段7计划决策1、11-monetization.md §11.4）：照片额度闸门
/// （`checkCanAddPhoto`/`addPhoto`）均先 `await subscriptionService.currentEntitlementIsPro()`
/// 现场重查权威 Pro 状态，再据此构造 `QuotaService` 判定——**不使用 `SubscriptionService.isPro`
/// 缓存值做放行依据**。`cachedIsPro` 仅供 `remainingPhotoSlots` 这类非放行 UI 提示
/// （如相册选择器 `maxSelectionCount`）使用。
@MainActor
@Observable
final class MomentEditorModel {
    let mode: EditorMode

    private let repository: MomentRepository
    private let subscriptionService: SubscriptionService

    /// 编辑态是否已完成从仓库载入；新建态恒为 `true`（无需等待异步载入）。
    private(set) var isLoaded: Bool

    /// 供非放行 UI 提示使用的 Pro 快照（见类型头部说明），启动时先取
    /// `subscriptionService.isPro` 缓存值，每次真实闸门判定后据当次权威结果刷新。
    private(set) var cachedIsPro: Bool

    var mood: Mood
    var title: String = ""
    var bodyText: String = ""
    var occurredAt: Date
    var selectedTagIDs: [UUID] = []
    var tagNamesByID: [UUID: String] = [:]
    var draftPhotos: [DraftPhoto] = []

    /// 打开时的字段快照，供 `isDirty` 比较（见 03-user-flows.md §3.1：取消若脏需二次确认）。
    private var baseline: EditorSnapshot

    /// `.edit` 态载入时既有的 `MomentImage.id` 列表（见 `save()`）：`updateMoment(imageDatas:)`
    /// 会级联删除旧 `MomentImage` 并按新顺序重建全新 id（即便照片内容未改动，见仓库层注释），
    /// 故保存成功后这些旧 id 对应的 `ThumbnailCache` 缓存必然是孤儿键，需逐个失效
    /// （见阶段 4 计划 §8 延后项、`docs/design/07-data-persistence.md` §5 缩略图缓存清理）。
    private var originalImageIDs: [UUID] = []

    init(
        mode: EditorMode,
        modelContainer: ModelContainer,
        subscriptionService: SubscriptionService,
        lastUsedMood: Mood = .normal
    ) {
        self.mode = mode
        self.repository = MomentRepository(modelContainer: modelContainer)
        self.subscriptionService = subscriptionService
        self.cachedIsPro = subscriptionService.isPro

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
            mood: initialMood, title: "", bodyText: "", occurredAt: initialOccurredAt, tagIDs: [],
            photos: []
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
        originalImageIDs = payload.snapshot.imageIDs
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

    // MARK: - 照片（见 04-screen-specs.md §4.4，压缩管线见 `ImageCompressor`）

    /// 追加照片前的额度校验：先现场重查 Pro 权威判定（决策1），UI 只消费该结果，不自行比较
    /// 数值（见 08-architecture.md §6）。
    func checkCanAddPhoto() async -> QuotaCheck {
        let quotaService = await makeQuotaService()
        return quotaService.checkCanAddPhoto(currentPhotoCount: draftPhotos.count)
    }

    /// 还可再添加的照片数（Pro 不限）：供选择器 `maxSelectionCount` 等**非放行** UI 派生，
    /// 用 `cachedIsPro` 快照即可（判定权威仍以 `checkCanAddPhoto`/`addPhoto` 的现场重查为准，
    /// 见类型头部说明）。
    var remainingPhotoSlots: Int {
        QuotaService(entitlementProvider: SubscriptionEntitlementProvider(isPro: cachedIsPro))
            .remainingPhotoSlots(currentPhotoCount: draftPhotos.count)
    }

    /// 追加一张已压缩的照片：先现场重查 Pro 权威判定（决策1），额度校验用当前草稿照片数
    /// （草稿即完整当前状态，见类型头部）。单次追加场景使用（如 DEBUG 照片注入钩子）；
    /// 同一批次追加多张照片请改用 `makeCurrentQuotaService()` + `addPhoto(_:using:)`
    /// （见二者说明，阶段7 review 修复：避免批量追加时逐张重复查询 Pro）。
    @discardableResult
    func addPhoto(_ jpegData: Data) async -> QuotaCheck {
        let quotaService = await makeQuotaService()
        return addPhoto(jpegData, using: quotaService)
    }

    /// 供批量追加照片场景（如相册一次选中多张，见 `EditorPhotoSection.appendPickedPhotos`）
    /// 在循环开始前提前查询一次 Pro 权威判定并复用：额度判定仍完整落在 `QuotaService`
    /// （决策1、08-architecture.md §6 不变），本方法只是把「查 Pro」这一步 IO 从循环体内提到
    /// 循环外，避免每张照片都重复现场重查（阶段7 review 修复）。
    func makeCurrentQuotaService() async -> QuotaService {
        await makeQuotaService()
    }

    /// 追加一张已压缩的照片，使用调用方已持有的 `quotaService`（不再重新查询 Pro，见
    /// `makeCurrentQuotaService()`）：额度校验用当前草稿照片数（草稿即完整当前状态）。
    @discardableResult
    func addPhoto(_ jpegData: Data, using quotaService: QuotaService) -> QuotaCheck {
        let check = quotaService.checkCanAddPhoto(currentPhotoCount: draftPhotos.count)
        if case .allowed = check {
            draftPhotos.append(DraftPhoto(jpegData: jpegData))
        }
        return check
    }

    /// 现场重查 Pro 权威判定并构造对应 `QuotaService`（决策1，见类型头部）：三处额度闸门中
    /// 属于本类型的两处（照片/标签）共用本方法，避免重复；同时刷新 `cachedIsPro`。
    private func makeQuotaService() async -> QuotaService {
        let isPro = await subscriptionService.currentEntitlementIsPro()
        cachedIsPro = isPro
        return QuotaService(entitlementProvider: SubscriptionEntitlementProvider(isPro: isPro))
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
            // 旧 MomentImage 已被级联删除、按新顺序重建为全新 id（见 originalImageIDs 注释），
            // 逐个失效对应的缩略图缓存键，避免孤儿缓存永久占用（07 §5）。
            for imageID in originalImageIDs {
                await ThumbnailCache.shared.removeThumbnail(for: imageID)
            }
        }
    }
}
