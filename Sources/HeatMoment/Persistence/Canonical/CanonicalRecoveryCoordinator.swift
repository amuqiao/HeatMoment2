import Foundation
import GRDB

enum CanonicalRecoveryCoordinatorError: Error, Equatable {
    case incompatibleRecoveryPoint(UUID)
    case recoveryPointUnavailable(UUID)
}

protocol CanonicalRestoreExecuting: Sendable {
    func stageRestore(
        recoveryPointID: UUID,
        restoreJobID: UUID,
        restoredSyncEpoch: UUID,
        now: Date
    ) throws -> CanonicalPendingRestoreContext

    func armStagedRestore(context: CanonicalPendingRestoreContext) throws
    func updateStagedRestoreContext(context: CanonicalPendingRestoreContext) throws
    func clearPendingRestore() throws
}

extension CanonicalRestoreExecutor: CanonicalRestoreExecuting {}

enum CanonicalRestoreRetentionStatus: Sendable, Equatable {
    case completed(evictedRecoveryPointIDs: [UUID])
    case failedAfterRestoreArmed(String)
}

struct CanonicalPreparedRestore: Sendable, Equatable {
    let selectedRecoveryPoint: CanonicalRecoveryPointRecord
    let restoreSafetyRecoveryPoint: CanonicalRecoveryPointRecord
    let pendingContext: CanonicalPendingRestoreContext
    let retentionStatus: CanonicalRestoreRetentionStatus
}

actor CanonicalRecoveryCoordinator {
    private let runtime: CanonicalLibraryRuntime
    private let appVersion: String
    private let stableChangeMinimumInterval: TimeInterval
    private let makeRestoreExecutor:
        @Sendable (
            CanonicalLibraryRuntime
        ) throws -> any CanonicalRestoreExecuting
    private let enforceRecoveryPointRetention: @Sendable (CanonicalLibraryRuntime) throws -> [UUID]
    private var didLoadLastStableChangeRecoveryPoint = false
    private var isCreatingStableChangeRecoveryPoint = false
    private var lastStableChangeRecoveryPointAt: Date?

    init(
        runtime: CanonicalLibraryRuntime,
        appVersion: String,
        stableChangeMinimumInterval: TimeInterval = 300,
        makeRestoreExecutor:
            @escaping @Sendable (
                CanonicalLibraryRuntime
            ) throws -> any CanonicalRestoreExecuting = { runtime in
                try CanonicalRestoreExecutor(runtime: runtime)
            },
        enforceRecoveryPointRetention:
            @escaping @Sendable (
                CanonicalLibraryRuntime
            ) throws -> [UUID] = { runtime in
                try runtime.recoveryPointSnapshotService.enforceRecoveryPointRetention()
            }
    ) {
        self.runtime = runtime
        self.appVersion = appVersion
        self.stableChangeMinimumInterval = stableChangeMinimumInterval
        self.makeRestoreExecutor = makeRestoreExecutor
        self.enforceRecoveryPointRetention = enforceRecoveryPointRetention
    }

    @discardableResult
    func createRecoveryPoint(
        reason: CanonicalRecoveryPointReason = .stableChanges,
        id: UUID = UUID(),
        createdAt: Date = .now,
        enforcesRetention: Bool = true
    ) throws -> CanonicalRecoveryPointRecord {
        try runtime.recoveryPointSnapshotService.createRecoveryPoint(
            RecoveryPointSnapshotRequest(
                id: id,
                reason: reason,
                createdAt: createdAt,
                appVersion: appVersion
            ),
            enforcesRetention: enforcesRetention
        )
        .recoveryPoint
    }

    @discardableResult
    func createStableChangesRecoveryPointIfNeeded(
        id: UUID = UUID(),
        createdAt: Date = .now
    ) throws -> CanonicalRecoveryPointRecord? {
        guard !isCreatingStableChangeRecoveryPoint else { return nil }
        isCreatingStableChangeRecoveryPoint = true
        defer { isCreatingStableChangeRecoveryPoint = false }

        try loadLastStableChangeRecoveryPointIfNeeded()
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
            let record = try createRecoveryPoint(
                reason: .stableChanges,
                id: id,
                createdAt: createdAt
            )
            lastStableChangeRecoveryPointAt = record.createdAt
            return record
        } catch {
            lastStableChangeRecoveryPointAt = previousStableChangeRecoveryPointAt
            throw error
        }
    }

    @discardableResult
    func createMutationSafetyRecoveryPoint(
        id: UUID = UUID(),
        createdAt: Date = .now
    ) throws -> CanonicalRecoveryPointRecord {
        try createRecoveryPoint(
            reason: .mutationSafety,
            id: id,
            createdAt: createdAt
        )
    }

    func listRecoveryPoints() throws -> [CanonicalRecoveryPointRecord] {
        try runtime.recoveryPointStore.listRecoveryPoints()
    }

    func currentCounts() throws -> CanonicalRecoveryPointCounts {
        try runtime.store.read { db in
            let recordCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM moment_record") ?? 0
            let usedTagCount =
                try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT tag_id) FROM moment_tag_link")
                ?? 0
            let assetCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM asset_record") ?? 0
            return CanonicalRecoveryPointCounts(
                recordCount: recordCount,
                usedTagCount: usedTagCount,
                assetCount: assetCount
            )
        }
    }

    @discardableResult
    func validateRecoveryPoint(id: UUID) throws -> CanonicalRecoveryPointRecord {
        try runtime.recoveryPointSnapshotService.validateRecoveryPoint(id: id)
    }

    @discardableResult
    func prepareRestore(
        id: UUID,
        restoreJobID: UUID = UUID(),
        restoredSyncEpoch: UUID = UUID(),
        restoreSafetyID: UUID = UUID(),
        now: Date = .now
    ) throws -> CanonicalPreparedRestore {
        let selected = try validateRecoveryPoint(id: id)
        guard selected.status == .available else {
            throw CanonicalRecoveryCoordinatorError.recoveryPointUnavailable(id)
        }
        try assertCompatibleForRestore(selected)

        let executor = try makeRestoreExecutor(runtime)
        var pendingContext = try executor.stageRestore(
            recoveryPointID: selected.id,
            restoreJobID: restoreJobID,
            restoredSyncEpoch: restoredSyncEpoch,
            now: now
        )
        var restoreSafetyIDToCleanUp: UUID?
        var didArmPendingRestore = false
        do {
            let restoreSafety = try createRecoveryPoint(
                reason: .restoreSafety,
                id: restoreSafetyID,
                createdAt: now,
                enforcesRetention: false
            )
            restoreSafetyIDToCleanUp = restoreSafety.id
            pendingContext.restoreSafetyRecoveryPoint = restoreSafety
            pendingContext.restoreSafetyAssetManifest = try runtime.recoveryPointStore
                .assetManifest(for: restoreSafety.id)
            try executor.updateStagedRestoreContext(context: pendingContext)
            try executor.armStagedRestore(context: pendingContext)
            didArmPendingRestore = true
            let retentionStatus: CanonicalRestoreRetentionStatus
            do {
                let evictedIDs = try enforceRecoveryPointRetention(runtime)
                retentionStatus = .completed(evictedRecoveryPointIDs: evictedIDs)
            } catch {
                retentionStatus = .failedAfterRestoreArmed(String(describing: error))
            }
            return CanonicalPreparedRestore(
                selectedRecoveryPoint: selected,
                restoreSafetyRecoveryPoint: restoreSafety,
                pendingContext: pendingContext,
                retentionStatus: retentionStatus
            )
        } catch {
            if !didArmPendingRestore {
                try executor.clearPendingRestore()
                if let restoreSafetyIDToCleanUp {
                    try runtime.recoveryPointSnapshotService.deleteRecoveryPoint(
                        id: restoreSafetyIDToCleanUp
                    )
                }
            }
            throw error
        }
    }
}

private extension CanonicalRecoveryCoordinator {
    func assertCompatibleForRestore(_ record: CanonicalRecoveryPointRecord) throws {
        let metadata = try currentMetadata()
        guard
            record.schemaVersion == metadata.schemaVersion,
            record.appVersion == appVersion,
            record.sourceLibraryID == metadata.libraryID
        else {
            throw CanonicalRecoveryCoordinatorError.incompatibleRecoveryPoint(record.id)
        }
    }

    func currentMetadata() throws -> CanonicalLibraryMetadata {
        try runtime.store.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM library_metadata WHERE id = 1")
            else {
                throw DatabaseError(message: "Missing library metadata")
            }
            return try CanonicalLibraryMetadata(
                libraryID: row.canonicalUUID("library_id"),
                schemaVersion: row["schema_version"],
                deviceID: row.canonicalUUID("device_id"),
                syncEpoch: row.canonicalUUID("sync_epoch"),
                createdAt: row.canonicalDate("created_at"),
                updatedAt: row.canonicalDate("updated_at")
            )
        }
    }

    func loadLastStableChangeRecoveryPointIfNeeded() throws {
        guard !didLoadLastStableChangeRecoveryPoint else { return }
        let stableChangePoints = try runtime.recoveryPointStore.listRecoveryPoints()
            .filter { $0.reason == .stableChanges && $0.status == .available }
        lastStableChangeRecoveryPointAt = stableChangePoints.first?.createdAt
        didLoadLastStableChangeRecoveryPoint = true
    }
}
