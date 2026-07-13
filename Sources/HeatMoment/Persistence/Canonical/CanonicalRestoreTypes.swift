import Foundation

enum CanonicalBootRestoreResult: Equatable {
    case none
    case restored(CanonicalPendingRestoreContext)
    case failed(CanonicalBootRestoreFailure)

    var failure: CanonicalBootRestoreFailure? {
        if case let .failed(failure) = self {
            return failure
        }
        return nil
    }
}

struct CanonicalBootRestoreFailure: Error, Equatable, CustomStringConvertible {
    let underlyingDescription: String
    let context: CanonicalPendingRestoreContext?

    init(underlying: Error, context: CanonicalPendingRestoreContext? = nil) {
        underlyingDescription = String(describing: underlying)
        self.context = context
    }

    var description: String {
        "canonical 本地恢复失败：\(underlyingDescription)"
    }
}

enum CanonicalRestoreCriticalError: Error {
    case rollbackFailed(Error)
}

enum CanonicalRestoreExecutorError: Error, Equatable {
    case runtimeRequiresDescriptor
    case recoveryPointUnavailable(UUID)
    case recoveryPointNotFound(UUID)
    case missingPendingContext
    case pendingContextMismatch
    case invalidArmedMarkerEncoding
    case armedMarkerMismatch(expected: String, actual: String)
    case invalidRelativePath(String)
    case fileOutsideRoot(String)
    case missingPayload(String)
    case snapshotByteCountMismatch(expected: Int64, actual: Int64)
    case snapshotHashMismatch(expected: String, actual: String)
    case snapshotSchemaVersionMismatch(expected: Int, actual: Int)
    case catalogCountsMismatch(
        expected: CanonicalRecoveryPointCounts,
        actual: CanonicalRecoveryPointCounts
    )
    case assetManifestMismatch
    case missingAssetBlob(String)
    case corruptAssetBlob(String)
    case assetByteCountMismatch(assetID: UUID, expected: Int64, actual: Int64)
    case cleanupFailed(originalError: String, cleanupError: String)
}

struct CanonicalPendingRestoreContext: Codable, Sendable, Equatable {
    let restoreJobID: UUID
    let selectedRecoveryPointID: UUID
    let selectedCreatedAt: Date
    let currentLibraryID: UUID
    let currentDeviceID: UUID
    let currentLibraryCreatedAt: Date
    let restoredSyncEpoch: UUID
    let schemaVersion: Int
    let appVersion: String
    let snapshot: CanonicalPendingRestoreSnapshot
    let counts: CanonicalPendingRestoreCounts
    let assetManifest: [CanonicalPendingRestoreAsset]
    var restoreSafetyRecoveryPoint: CanonicalRecoveryPointRecord?
    var restoreSafetyAssetManifest: [CanonicalRecoveryPointAssetRecord]

    init(
        restoreJobID: UUID,
        selectedRecoveryPointID: UUID,
        selectedCreatedAt: Date,
        currentLibraryID: UUID,
        currentDeviceID: UUID,
        currentLibraryCreatedAt: Date,
        restoredSyncEpoch: UUID,
        schemaVersion: Int,
        appVersion: String,
        snapshot: CanonicalPendingRestoreSnapshot,
        counts: CanonicalPendingRestoreCounts,
        assetManifest: [CanonicalPendingRestoreAsset],
        restoreSafetyRecoveryPoint: CanonicalRecoveryPointRecord? = nil,
        restoreSafetyAssetManifest: [CanonicalRecoveryPointAssetRecord] = []
    ) {
        self.restoreJobID = restoreJobID
        self.selectedRecoveryPointID = selectedRecoveryPointID
        self.selectedCreatedAt = selectedCreatedAt
        self.currentLibraryID = currentLibraryID
        self.currentDeviceID = currentDeviceID
        self.currentLibraryCreatedAt = currentLibraryCreatedAt
        self.restoredSyncEpoch = restoredSyncEpoch
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.snapshot = snapshot
        self.counts = counts
        self.assetManifest = assetManifest
        self.restoreSafetyRecoveryPoint = restoreSafetyRecoveryPoint
        self.restoreSafetyAssetManifest = restoreSafetyAssetManifest
    }
}

struct CanonicalPendingRestoreSnapshot: Codable, Sendable, Equatable {
    let relativePath: String
    let byteCount: Int64
    let sha256: String
}

struct CanonicalPendingRestoreCounts: Codable, Sendable, Equatable {
    let recordCount: Int
    let usedTagCount: Int
    let assetCount: Int
}

struct CanonicalPendingRestoreAsset: Codable, Sendable, Equatable {
    let assetID: UUID
    let contentHash: String
    let byteCount: Int64
    let relativePath: String
}

extension CanonicalPendingRestoreAsset {
    init(record: CanonicalRecoveryPointAssetRecord) {
        assetID = record.assetID
        contentHash = record.contentHash
        byteCount = record.byteCount
        relativePath = record.relativePath
    }
}
