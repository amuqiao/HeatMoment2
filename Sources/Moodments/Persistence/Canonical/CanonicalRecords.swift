import Foundation
import GRDB

enum CanonicalMomentLifecycleState: String, Sendable, Equatable {
    case active
    case softDeleted
    case purgePending
    case purged
}

struct CanonicalMomentRecord: Sendable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let bodyText: String
    let occurredAt: Date
    let createdAt: Date
    let updatedAt: Date
    let mood: Mood
    let tagIDs: [UUID]
    let lifecycleState: CanonicalMomentLifecycleState
    let deletedAt: Date?
    let purgedAt: Date?
    let revision: Int

    var isDeleted: Bool { lifecycleState == .softDeleted }

    var isTerminalDeletion: Bool {
        lifecycleState == .purgePending || lifecycleState == .purged
    }
}

struct CanonicalTagRecord: Sendable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let createdAt: Date
    let revision: Int
}

struct CanonicalMutationRecord: Sendable, Identifiable, Equatable {
    let id: UUID
    let entityType: String
    let entityID: UUID
    let operation: String
    let occurredAt: Date
    let deviceID: UUID
    let recordRevision: Int
}

enum CanonicalAssetPinOwnerKind: String, Sendable, Equatable, CaseIterable {
    case recoveryPoint
    case restoreStaging
    case exportJob
    case sync
}

struct CanonicalAssetPinRecord: Sendable, Identifiable, Equatable {
    let id: UUID
    let contentHash: String
    let ownerKind: CanonicalAssetPinOwnerKind
    let ownerID: String
    let createdAt: Date
    let expiresAt: Date?

    func isActive(at date: Date) -> Bool {
        expiresAt.map { $0 > date } ?? true
    }
}

enum CanonicalRecoveryPointReason: String, Sendable, Equatable, CaseIterable {
    case mutationSafety
    case schemaMigration
    case restoreSafety
    case stableChanges
}

enum CanonicalRecoveryPointStatus: String, Sendable, Equatable, CaseIterable {
    case available
    case invalid
}

struct CanonicalRecoveryPointCounts: Sendable, Equatable {
    let recordCount: Int
    let tagCount: Int
    let assetCount: Int
}

struct CanonicalRecoveryPointSnapshot: Sendable, Equatable {
    let relativePath: String
    let byteCount: Int64
    let sha256: String
}

struct CanonicalRecoveryPointRecord: Sendable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let reason: CanonicalRecoveryPointReason
    let status: CanonicalRecoveryPointStatus
    let schemaVersion: Int
    let appVersion: String
    let sourceLibraryID: UUID
    let sqliteSnapshot: CanonicalRecoveryPointSnapshot
    let counts: CanonicalRecoveryPointCounts
}

struct CanonicalRecoveryPointAssetRecord: Sendable, Equatable {
    let recoveryPointID: UUID
    let assetID: UUID
    let contentHash: String
    let byteCount: Int64
    let relativePath: String
}

struct CanonicalRecoveryPointCreationRequest: Sendable, Equatable {
    let id: UUID
    let reason: CanonicalRecoveryPointReason
    let createdAt: Date
    let schemaVersion: Int
    let appVersion: String
    let sourceLibraryID: UUID
    let sqliteSnapshot: CanonicalRecoveryPointSnapshot
    let counts: CanonicalRecoveryPointCounts
    let assetManifest: [CanonicalRecoveryPointAssetRecord]
}

struct CanonicalRecoveryPointCreationResult: Sendable, Equatable {
    let recoveryPoint: CanonicalRecoveryPointRecord
    let evictedRecoveryPointIDs: [UUID]
}

struct CanonicalLibraryMetadata: Sendable, Equatable {
    let libraryID: UUID
    let schemaVersion: Int
    let deviceID: UUID
    let syncEpoch: UUID
    let createdAt: Date
    let updatedAt: Date
    let swiftDataImportedAt: Date?
    let swiftDataImportSourceFingerprint: String?
}

extension Date {
    fileprivate init(canonicalTimestamp: Double) {
        self.init(timeIntervalSince1970: canonicalTimestamp)
    }

    fileprivate var canonicalTimestamp: Double {
        timeIntervalSince1970
    }
}

extension UUID {
    init(canonicalString: String) throws {
        guard let uuid = UUID(uuidString: canonicalString) else {
            throw DatabaseError(message: "Invalid UUID: \(canonicalString)")
        }
        self = uuid
    }
}

extension Row {
    func canonicalUUID(_ column: String) throws -> UUID {
        try UUID(canonicalString: self[column])
    }

    func canonicalDate(_ column: String) -> Date {
        Date(canonicalTimestamp: self[column])
    }

    func canonicalOptionalDate(_ column: String) -> Date? {
        let value: Double? = self[column]
        return value.map(Date.init(canonicalTimestamp:))
    }
}
