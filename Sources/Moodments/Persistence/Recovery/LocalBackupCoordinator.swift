import Foundation

actor LocalBackupCoordinator {
    private let descriptor: LocalBackupStoreDescriptor
    private let recoveryPointManager: RecoveryPointManager
    private let countsRepository: RecoveryPointCountsRepository
    private let appVersion: String
    private let schemaVersion: Int
    private let stableChangeMinimumInterval: TimeInterval
    private var didLoadLastStableChangeRecoveryPoint = false
    private var isCreatingStableChangeRecoveryPoint = false
    private var lastStableChangeRecoveryPointAt: Date?

    init(
        descriptor: LocalBackupStoreDescriptor,
        recoveryPointManager: RecoveryPointManager,
        countsRepository: RecoveryPointCountsRepository,
        appVersion: String,
        schemaVersion: Int = 1,
        stableChangeMinimumInterval: TimeInterval = 300
    ) {
        self.descriptor = descriptor
        self.recoveryPointManager = recoveryPointManager
        self.countsRepository = countsRepository
        self.appVersion = appVersion
        self.schemaVersion = schemaVersion
        self.stableChangeMinimumInterval = stableChangeMinimumInterval
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
    func createStableChangesRecoveryPointIfNeeded(
        createdAt: Date = .now
    ) async throws -> RecoveryPointMetadata? {
        guard !isCreatingStableChangeRecoveryPoint else { return nil }
        isCreatingStableChangeRecoveryPoint = true
        defer { isCreatingStableChangeRecoveryPoint = false }

        try await loadLastStableChangeRecoveryPointIfNeeded()
        let isWithinStableChangeWindow =
            lastStableChangeRecoveryPointAt.map {
                createdAt.timeIntervalSince($0) < stableChangeMinimumInterval
            } ?? false
        if isWithinStableChangeWindow {
            return nil
        }

        let previousStableChangeRecoveryPointAt = lastStableChangeRecoveryPointAt
        lastStableChangeRecoveryPointAt = createdAt
        do {
            let metadata = try await createRecoveryPoint(
                reason: .stableChanges,
                createdAt: createdAt
            )
            lastStableChangeRecoveryPointAt = metadata.createdAt
            return metadata
        } catch {
            lastStableChangeRecoveryPointAt = previousStableChangeRecoveryPointAt
            throw error
        }
    }

    @discardableResult
    func createMutationSafetyRecoveryPoint(
        createdAt: Date = .now
    ) async throws -> RecoveryPointMetadata {
        try await createRecoveryPoint(reason: .mutationSafety, createdAt: createdAt)
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
    func prepareRestore(id: UUID) async throws -> LocalBackupPendingRestoreContext {
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
            let restoreSafetyMetadata = try await createRecoveryPoint(reason: .restoreSafety)
            try LocalBackupRestoreExecutor.armStagedRestore(
                metadata: metadata,
                descriptor: descriptor,
                restoreSafetyMetadata: restoreSafetyMetadata
            )
            return LocalBackupPendingRestoreContext(
                selected: metadata,
                restoreSafety: restoreSafetyMetadata
            )
        } catch {
            try LocalBackupRestoreExecutor.clearPendingRestore(descriptor: descriptor)
            throw error
        }
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

    private func loadLastStableChangeRecoveryPointIfNeeded() async throws {
        guard !didLoadLastStableChangeRecoveryPoint else { return }
        let stableChangePoints = try await recoveryPointManager.listRecoveryPoints()
            .filter { $0.reason == .stableChanges && $0.status == .available }
        lastStableChangeRecoveryPointAt = stableChangePoints.first?.createdAt
        didLoadLastStableChangeRecoveryPoint = true
    }
}
