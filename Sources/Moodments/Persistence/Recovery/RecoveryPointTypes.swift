import Foundation

enum RecoveryPointError: Error, Equatable {
    case duplicatePayloadPath(String)
    case emptySource(URL)
    case incompatibleRecoveryPoint(UUID)
    case invalidMaxRecoveryPoints(Int)
    case payloadSourceCannotBeRoot(URL)
    case pendingRestoreMissingPayload
    case recoveryDirectoryIncluded(URL)
    case recoveryPointUnavailable(UUID)
    case recoveryPointNotFound(UUID)
    case sourceFileOutsideRoot(file: URL, root: URL)
}

enum RecoveryPointReason: String, Codable, Sendable, Equatable {
    case schemaMigration
    case restoreSafety
    case stableChanges
}

enum RecoveryPointStatus: String, Codable, Sendable, Equatable {
    case available
    case invalid
}

struct RecoveryPointCounts: Codable, Sendable, Equatable {
    let recordCount: Int
    let tagCount: Int
    let assetCount: Int
}

struct RecoveryPointFileManifest: Codable, Sendable, Equatable {
    let relativePath: String
    let sizeBytes: Int64
    let sha256: String
}

struct RecoveryPointMetadata: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let createdAt: Date
    let reason: RecoveryPointReason
    var status: RecoveryPointStatus
    let schemaVersion: Int
    let appVersion: String
    let sourceLibraryID: String?
    let counts: RecoveryPointCounts
    let payloadSizeBytes: Int64
    let files: [RecoveryPointFileManifest]
}

struct RecoveryPointPayloadSource: Sendable, Equatable {
    let rootDirectory: URL
    let includedURLs: [URL]
}
