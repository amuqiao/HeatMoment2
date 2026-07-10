import Foundation
import SwiftData

enum LocalLibraryMutationError: Error {
    case emptyTagName
    case quotaExceeded(QuotaKind)
    case mutationSafetyPointFailed(underlying: Error)
}

struct LocalLibraryTagMutationResult: Equatable {
    let id: UUID
    let name: String
    let didCreate: Bool
}

/// 本机资料库写入用例的应用服务。
///
/// 它不替代查询 repository，也不引入新的存储权威；当前仍委托 SwiftData repository。
/// 目标是把 UI 层散落的写入副作用收口到一个边界：本地写入标记、自动恢复点、
/// 高风险操作前安全点和缩略图失效。后续迁移到 canonical store 时，View 层优先保持不变。
@MainActor
struct LocalLibraryMutationService {
    private let modelContainer: ModelContainer
    private let localBackupCoordinator: LocalBackupCoordinator?
    private let syncStatusService: SyncStatusService
    private let errorPresenter: ErrorPresenter

    init(
        modelContainer: ModelContainer,
        localBackupCoordinator: LocalBackupCoordinator?,
        syncStatusService: SyncStatusService,
        errorPresenter: ErrorPresenter
    ) {
        self.modelContainer = modelContainer
        self.localBackupCoordinator = localBackupCoordinator
        self.syncStatusService = syncStatusService
        self.errorPresenter = errorPresenter
    }

    @discardableResult
    func createMoment(
        title: String,
        bodyText: String,
        occurredAt: Date,
        mood: Mood,
        tagIDs: [UUID],
        imageDatas: [Data],
        quotaService: QuotaService
    ) async throws -> UUID {
        let count = try await momentRepository.totalMomentCount()
        switch quotaService.checkCanCreateMoment(currentMomentCount: count) {
        case .allowed:
            break
        case .exceeded(let kind):
            throw LocalLibraryMutationError.quotaExceeded(kind)
        }
        let id = try await momentRepository.createMoment(
            title: title,
            bodyText: bodyText,
            occurredAt: occurredAt,
            mood: mood,
            tagIDs: tagIDs,
            imageDatas: imageDatas
        )
        recordStableLocalWrite()
        return id
    }

    func updateMoment(
        id: UUID,
        title: String,
        bodyText: String,
        occurredAt: Date,
        mood: Mood,
        tagIDs: [UUID],
        imageDatas: [Data],
        replacingOriginalImageIDs originalImageIDs: [UUID]
    ) async throws {
        try await momentRepository.updateMoment(
            id: id,
            title: title,
            bodyText: bodyText,
            occurredAt: occurredAt,
            mood: mood,
            tagIDs: tagIDs,
            imageDatas: imageDatas
        )
        for imageID in originalImageIDs {
            await ThumbnailCache.shared.removeThumbnail(for: imageID)
        }
        recordStableLocalWrite()
    }

    func softDeleteMoment(id: UUID) async throws {
        try await momentRepository.softDelete(id: id)
        recordStableLocalWrite()
    }

    func restoreMoment(id: UUID) async throws {
        try await createMutationSafetyPoint()
        try await momentRepository.restore(id: id)
        recordLocalWrite()
    }

    func purgeMoment(id: UUID, imageIDs: [UUID]) async throws {
        try await createMutationSafetyPoint()
        try await momentRepository.purge(id: id)
        for imageID in imageIDs {
            await ThumbnailCache.shared.removeThumbnail(for: imageID)
        }
        recordLocalWrite()
    }

    @discardableResult
    func createOrReuseTag(
        name: String,
        quotaService: QuotaService
    ) async throws -> LocalLibraryTagMutationResult {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw LocalLibraryMutationError.emptyTagName
        }
        let result: TagCreateOrReuseResult
        do {
            result = try await tagRepository.createOrReuseTag(
                name: normalizedName,
                quotaService: quotaService
            )
        } catch RepositoryError.quotaExceeded(let kind) {
            throw LocalLibraryMutationError.quotaExceeded(kind)
        }
        guard result.didCreate else {
            return LocalLibraryTagMutationResult(
                id: result.id,
                name: result.name,
                didCreate: false
            )
        }
        recordStableLocalWrite()
        return LocalLibraryTagMutationResult(
            id: result.id,
            name: result.name,
            didCreate: true
        )
    }

    func renameTag(id: UUID, newName: String) async throws {
        let normalizedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw LocalLibraryMutationError.emptyTagName
        }
        try await tagRepository.renameTag(id: id, newName: normalizedName)
        recordStableLocalWrite()
    }

    func deleteTag(id: UUID) async throws {
        try await createMutationSafetyPoint()
        try await tagRepository.deleteTag(id: id)
        recordLocalWrite()
    }

    private var momentRepository: MomentRepository {
        MomentRepository(modelContainer: modelContainer)
    }

    private var tagRepository: TagRepository {
        TagRepository(modelContainer: modelContainer)
    }

    private func createMutationSafetyPoint() async throws {
        do {
            try await LocalBackupWriteRecorder.createMutationSafetyPoint(
                using: localBackupCoordinator
            )
        } catch {
            throw LocalLibraryMutationError.mutationSafetyPointFailed(underlying: error)
        }
    }

    private func recordStableLocalWrite() {
        recordLocalWrite()
        LocalBackupWriteRecorder.recordStableChanges(
            using: localBackupCoordinator,
            errorPresenter: errorPresenter
        )
    }

    private func recordLocalWrite() {
        syncStatusService.noteLocalWrite()
    }
}
