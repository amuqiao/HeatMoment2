import Foundation

actor LocalBackupCoordinator {
    private let descriptor: LocalBackupStoreDescriptor
    private let recoveryPointManager: RecoveryPointManager
    private let countsRepository: RecoveryPointCountsRepository
    private let appVersion: String
    private let schemaVersion: Int
    private var didCreateLaunchRecoveryPoint = false

    init(
        descriptor: LocalBackupStoreDescriptor,
        recoveryPointManager: RecoveryPointManager,
        countsRepository: RecoveryPointCountsRepository,
        appVersion: String,
        schemaVersion: Int = 1
    ) {
        self.descriptor = descriptor
        self.recoveryPointManager = recoveryPointManager
        self.countsRepository = countsRepository
        self.appVersion = appVersion
        self.schemaVersion = schemaVersion
    }

    @discardableResult
    func createRecoveryPoint(
        reason: RecoveryPointReason = .stableChanges,
        createdAt: Date = .now
    ) async throws -> RecoveryPointMetadata {
        let source = try descriptor.payloadSource()
        let counts = try await countsRepository.recoveryPointCounts()
        return try await recoveryPointManager.createRecoveryPoint(
            from: source,
            reason: reason,
            counts: counts,
            schemaVersion: schemaVersion,
            appVersion: appVersion,
            sourceLibraryID: descriptor.sourceLibraryID,
            createdAt: createdAt
        )
    }

    @discardableResult
    func createLaunchRecoveryPoint(
        reason: RecoveryPointReason = .stableChanges,
        createdAt: Date = .now
    ) async throws -> RecoveryPointMetadata? {
        guard !didCreateLaunchRecoveryPoint else { return nil }
        didCreateLaunchRecoveryPoint = true
        return try await createRecoveryPoint(reason: reason, createdAt: createdAt)
    }

    func listRecoveryPoints() async throws -> [RecoveryPointMetadata] {
        try await recoveryPointManager.listRecoveryPoints()
    }

    func currentCounts() async throws -> RecoveryPointCounts {
        try await countsRepository.recoveryPointCounts()
    }

    @discardableResult
    func validateRecoveryPoint(id: UUID) async throws -> RecoveryPointMetadata {
        try await recoveryPointManager.validateRecoveryPoint(id: id)
    }

    @discardableResult
    func prepareRestore(id: UUID) async throws -> RecoveryPointMetadata {
        let metadata = try await validateRecoveryPoint(id: id)
        guard metadata.status == .available else {
            throw RecoveryPointError.recoveryPointUnavailable(id)
        }
        try assertCompatibleForRestore(metadata)

        try LocalBackupRestoreExecutor.stageRestore(
            metadata: metadata,
            descriptor: descriptor
        )
        do {
            try await createRecoveryPoint(reason: .restoreSafety)
            try LocalBackupRestoreExecutor.armStagedRestore(
                metadata: metadata,
                descriptor: descriptor
            )
        } catch {
            try LocalBackupRestoreExecutor.clearPendingRestore(descriptor: descriptor)
            throw error
        }
        return metadata
    }

    private func assertCompatibleForRestore(_ metadata: RecoveryPointMetadata) throws {
        guard
            metadata.schemaVersion == schemaVersion,
            metadata.appVersion == appVersion,
            metadata.sourceLibraryID == descriptor.sourceLibraryID
        else {
            throw RecoveryPointError.incompatibleRecoveryPoint(metadata.id)
        }
    }
}
