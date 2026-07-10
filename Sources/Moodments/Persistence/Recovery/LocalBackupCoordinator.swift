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
}
