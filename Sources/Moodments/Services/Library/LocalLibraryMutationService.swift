import Foundation
#if DEBUG
    import SwiftData
#endif

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
/// 它不替代查询 repository，也不引入新的存储权威；生产主流程显式委托 canonical repository，
/// SwiftData backend 仅保留给尚未迁移的测试/过渡调用方。
/// 目标是把 UI 层散落的写入副作用收口到一个边界：本地写入标记、自动恢复点、
/// 高风险操作前安全点和缩略图失效。后续迁移到 canonical store 时，View 层优先保持不变。
@MainActor
struct LocalLibraryMutationService {
    private enum Backend {
        #if DEBUG
            case swiftData(ModelContainer)
        #endif
        case canonical(CanonicalLibraryService)
    }

    private let backend: Backend
    private let localBackupCoordinator: LocalBackupCoordinator?
    private let canonicalRecoveryCoordinator: CanonicalRecoveryCoordinator?
    private let syncStatusService: SyncStatusService
    private let errorPresenter: ErrorPresenter

    #if DEBUG
        init(
            modelContainer: ModelContainer,
            localBackupCoordinator: LocalBackupCoordinator?,
            syncStatusService: SyncStatusService,
            errorPresenter: ErrorPresenter
        ) {
            self.backend = .swiftData(modelContainer)
            self.localBackupCoordinator = localBackupCoordinator
            self.canonicalRecoveryCoordinator = nil
            self.syncStatusService = syncStatusService
            self.errorPresenter = errorPresenter
        }
    #endif

    init(
        canonicalService: CanonicalLibraryService,
        localBackupCoordinator: LocalBackupCoordinator?,
        canonicalRecoveryCoordinator: CanonicalRecoveryCoordinator? = nil,
        syncStatusService: SyncStatusService,
        errorPresenter: ErrorPresenter
    ) {
        self.backend = .canonical(canonicalService)
        self.localBackupCoordinator = localBackupCoordinator
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
        let count = try await totalMomentCount()
        switch quotaService.checkCanCreateMoment(currentMomentCount: count) {
        case .allowed:
            break
        case .exceeded(let kind):
            throw LocalLibraryMutationError.quotaExceeded(kind)
        }
        let id = try await createMomentInRepository(
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
        try await updateMomentInRepository(
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
        try await softDeleteMomentInRepository(id: id)
        recordStableLocalWrite()
    }

    func restoreMoment(id: UUID) async throws {
        try await createMutationSafetyPoint()
        try await restoreMomentInRepository(id: id)
        recordLocalWrite()
    }

    func purgeMoment(id: UUID, imageIDs: [UUID]) async throws {
        try await createMutationSafetyPoint()
        try await purgeMomentInRepository(id: id)
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
            result = try await createOrReuseTagInRepository(
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
        try await renameTagInRepository(id: id, newName: normalizedName)
        recordStableLocalWrite()
    }

    func deleteTag(id: UUID) async throws {
        try await createMutationSafetyPoint()
        try await deleteTagInRepository(id: id)
        recordLocalWrite()
    }

    private func totalMomentCount() async throws -> Int {
        switch backend {
        #if DEBUG
            case let .swiftData(modelContainer):
                try await MomentRepository(modelContainer: modelContainer).totalMomentCount()
        #endif
        case let .canonical(service):
            try await service.repository.totalMomentCount()
        }
    }

    @discardableResult
    private func createMomentInRepository(
        title: String,
        bodyText: String,
        occurredAt: Date,
        mood: Mood,
        tagIDs: [UUID],
        imageDatas: [Data]
    ) async throws -> UUID {
        switch backend {
        #if DEBUG
            case let .swiftData(modelContainer):
                return try await MomentRepository(modelContainer: modelContainer).createMoment(
                    title: title,
                    bodyText: bodyText,
                    occurredAt: occurredAt,
                    mood: mood,
                    tagIDs: tagIDs,
                    imageDatas: imageDatas
                )
        #endif
        case let .canonical(service):
            let id = try await service.repository.createMoment(
                title: title,
                bodyText: bodyText,
                occurredAt: occurredAt,
                mood: mood,
                tagIDs: tagIDs,
                imageDatas: imageDatas
            )
            service.noteCanonicalChange()
            return id
        }
    }

    private func updateMomentInRepository(
        id: UUID,
        title: String,
        bodyText: String,
        occurredAt: Date,
        mood: Mood,
        tagIDs: [UUID],
        imageDatas: [Data]
    ) async throws {
        switch backend {
        #if DEBUG
            case let .swiftData(modelContainer):
                try await MomentRepository(modelContainer: modelContainer).updateMoment(
                    id: id,
                    title: title,
                    bodyText: bodyText,
                    occurredAt: occurredAt,
                    mood: mood,
                    tagIDs: tagIDs,
                    imageDatas: imageDatas
                )
        #endif
        case let .canonical(service):
            try await service.repository.updateMoment(
                id: id,
                title: title,
                bodyText: bodyText,
                occurredAt: occurredAt,
                mood: mood,
                tagIDs: tagIDs,
                imageDatas: imageDatas
            )
            service.noteCanonicalChange()
        }
    }

    private func softDeleteMomentInRepository(id: UUID) async throws {
        switch backend {
        #if DEBUG
            case let .swiftData(modelContainer):
                try await MomentRepository(modelContainer: modelContainer).softDelete(id: id)
        #endif
        case let .canonical(service):
            try await service.repository.softDeleteMoment(id: id)
            service.noteCanonicalChange()
        }
    }

    private func restoreMomentInRepository(id: UUID) async throws {
        switch backend {
        #if DEBUG
            case let .swiftData(modelContainer):
                try await MomentRepository(modelContainer: modelContainer).restore(id: id)
        #endif
        case let .canonical(service):
            try await service.repository.restoreMoment(id: id)
            service.noteCanonicalChange()
        }
    }

    private func purgeMomentInRepository(id: UUID) async throws {
        switch backend {
        #if DEBUG
            case let .swiftData(modelContainer):
                try await MomentRepository(modelContainer: modelContainer).purge(id: id)
        #endif
        case let .canonical(service):
            try await service.repository.purgeMoment(id: id)
            service.noteCanonicalChange()
        }
    }

    private func createOrReuseTagInRepository(
        name: String,
        quotaService: QuotaService
    ) async throws -> TagCreateOrReuseResult {
        switch backend {
        #if DEBUG
            case let .swiftData(modelContainer):
                return try await TagRepository(modelContainer: modelContainer).createOrReuseTag(
                    name: name,
                    quotaService: quotaService
                )
        #endif
        case let .canonical(service):
            let result = try await service.repository.createOrReuseTag(
                name: name,
                quotaService: quotaService
            )
            if result.didCreate {
                service.noteCanonicalChange()
            }
            return result
        }
    }

    private func renameTagInRepository(id: UUID, newName: String) async throws {
        switch backend {
        #if DEBUG
            case let .swiftData(modelContainer):
                try await TagRepository(modelContainer: modelContainer).renameTag(
                    id: id, newName: newName)
        #endif
        case let .canonical(service):
            try await service.repository.renameTag(id: id, newName: newName)
            service.noteCanonicalChange()
        }
    }

    private func deleteTagInRepository(id: UUID) async throws {
        switch backend {
        #if DEBUG
            case let .swiftData(modelContainer):
                try await TagRepository(modelContainer: modelContainer).deleteTag(id: id)
        #endif
        case let .canonical(service):
            try await service.repository.deleteTag(id: id)
            service.noteCanonicalChange()
        }
    }

    private func createMutationSafetyPoint() async throws {
        do {
            switch backend {
            #if DEBUG
                case .swiftData:
                    try await LocalBackupWriteRecorder.createMutationSafetyPoint(
                        using: localBackupCoordinator
                    )
            #endif
            case .canonical:
                try await CanonicalRecoveryWriteRecorder.createMutationSafetyPoint(
                    using: canonicalRecoveryCoordinator
                )
            }
        } catch {
            throw LocalLibraryMutationError.mutationSafetyPointFailed(underlying: error)
        }
    }

    private func recordStableLocalWrite() {
        recordLocalWrite()
        switch backend {
        #if DEBUG
            case .swiftData:
                LocalBackupWriteRecorder.recordStableChanges(
                    using: localBackupCoordinator,
                    errorPresenter: errorPresenter
                )
        #endif
        case .canonical:
            CanonicalRecoveryWriteRecorder.recordStableChanges(
                using: canonicalRecoveryCoordinator,
                errorPresenter: errorPresenter
            )
        }
    }

    private func recordLocalWrite() {
        syncStatusService.noteLocalWrite()
    }
}
