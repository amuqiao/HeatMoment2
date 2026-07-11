import Foundation

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
/// 本服务只编排 canonical repository 写入、恢复点、安全点、同步状态和缩略图失效；
/// 不保留旧存储 backend。
@MainActor
struct LocalLibraryMutationService {
    private let canonicalService: CanonicalLibraryService
    private let canonicalRecoveryCoordinator: CanonicalRecoveryCoordinator?
    private let syncStatusService: SyncStatusService
    private let errorPresenter: ErrorPresenter

    init(
        canonicalService: CanonicalLibraryService,
        canonicalRecoveryCoordinator: CanonicalRecoveryCoordinator? = nil,
        syncStatusService: SyncStatusService,
        errorPresenter: ErrorPresenter
    ) {
        self.canonicalService = canonicalService
        self.canonicalRecoveryCoordinator = canonicalRecoveryCoordinator
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
        let count = try await canonicalService.repository.totalMomentCount()
        switch quotaService.checkCanCreateMoment(currentMomentCount: count) {
        case .allowed:
            break
        case .exceeded(let kind):
            throw LocalLibraryMutationError.quotaExceeded(kind)
        }
        let id = try await canonicalService.repository.createMoment(
            title: title,
            bodyText: bodyText,
            occurredAt: occurredAt,
            mood: mood,
            tagIDs: tagIDs,
            imageDatas: imageDatas
        )
        canonicalService.noteCanonicalChange()
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
        try await canonicalService.repository.updateMoment(
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
        canonicalService.noteCanonicalChange()
        recordStableLocalWrite()
    }

    func softDeleteMoment(id: UUID) async throws {
        try await canonicalService.repository.softDeleteMoment(id: id)
        canonicalService.noteCanonicalChange()
        recordStableLocalWrite()
    }

    func restoreMoment(id: UUID) async throws {
        try await createMutationSafetyPoint()
        try await canonicalService.repository.restoreMoment(id: id)
        canonicalService.noteCanonicalChange()
        recordLocalWrite()
    }

    func purgeMoment(id: UUID, imageIDs: [UUID]) async throws {
        try await createMutationSafetyPoint()
        try await canonicalService.repository.purgeMoment(id: id)
        for imageID in imageIDs {
            await ThumbnailCache.shared.removeThumbnail(for: imageID)
        }
        canonicalService.noteCanonicalChange()
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
            result = try await canonicalService.repository.createOrReuseTag(
                name: normalizedName,
                quotaService: quotaService
            )
        } catch RepositoryError.quotaExceeded(let kind) {
            throw LocalLibraryMutationError.quotaExceeded(kind)
        }
        if result.didCreate {
            canonicalService.noteCanonicalChange()
            recordStableLocalWrite()
        }
        return LocalLibraryTagMutationResult(
            id: result.id,
            name: result.name,
            didCreate: result.didCreate
        )
    }

    func renameTag(id: UUID, newName: String) async throws {
        let normalizedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw LocalLibraryMutationError.emptyTagName
        }
        try await canonicalService.repository.renameTag(id: id, newName: normalizedName)
        canonicalService.noteCanonicalChange()
        recordStableLocalWrite()
    }

    func deleteTag(id: UUID) async throws {
        try await createMutationSafetyPoint()
        try await canonicalService.repository.deleteTag(id: id)
        canonicalService.noteCanonicalChange()
        recordLocalWrite()
    }

    private func createMutationSafetyPoint() async throws {
        do {
            try await CanonicalRecoveryWriteRecorder.createMutationSafetyPoint(
                using: canonicalRecoveryCoordinator
            )
        } catch {
            throw LocalLibraryMutationError.mutationSafetyPointFailed(underlying: error)
        }
    }

    private func recordStableLocalWrite() {
        recordLocalWrite()
        CanonicalRecoveryWriteRecorder.recordStableChanges(
            using: canonicalRecoveryCoordinator,
            errorPresenter: errorPresenter
        )
    }

    private func recordLocalWrite() {
        syncStatusService.noteLocalWrite()
    }
}
