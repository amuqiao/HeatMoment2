import Foundation

protocol BackupPackageServicing: Sendable {
    func currentSummary() async throws -> BackupPackageLibrarySummary
    func exportPackage(createdAt: Date) async throws -> BackupPackageExportResult
    func inspectPackage(at url: URL) async throws -> BackupPackagePreview
    func prepareImport(_ preview: BackupPackagePreview, now: Date) async throws
        -> BackupPackagePreparedImport
}

extension BackupPackageServicing {
    func exportPackage() async throws -> BackupPackageExportResult {
        try await exportPackage(createdAt: .now)
    }

    func prepareImport(_ preview: BackupPackagePreview) async throws -> BackupPackagePreparedImport {
        try await prepareImport(preview, now: .now)
    }
}

struct BackupPackageLibrarySummary: Sendable, Equatable {
    let counts: BackupRecoveryCounts
    let lastExportedAt: Date?
}

struct BackupPackageExportResult: Sendable, Equatable {
    let packageID: UUID
    let createdAt: Date
    let fileURL: URL
    let byteCount: Int64
    let sha256: String
    let counts: BackupRecoveryCounts
}

struct BackupPackagePreview: Identifiable, Sendable, Equatable {
    let id: UUID
    let createdAt: Date
    let sourceAppVersion: String
    let sourceSchemaVersion: Int
    let sourceLibraryID: UUID
    let packageURL: URL
    let stagingDirectory: URL
    let manifest: BackupPackageManifest
    let counts: BackupRecoveryCounts
}

struct BackupPackagePreparedImport: Sendable, Equatable {
    let pendingContext: BackupPendingRestoreContext
    let packageID: UUID
    let packageCreatedAt: Date
    let retentionStatus: BackupPackageRestoreRetentionStatus
}

enum BackupPackageRestoreRetentionStatus: Sendable, Equatable {
    case completed
    case failedAfterRestoreArmed(String)
}

enum BackupPackageError: Error, Equatable {
    case runtimeRequiresDescriptor
    case unsupportedFormatVersion(Int)
    case unsupportedSchemaVersion(expected: Int, actual: Int)
    case invalidMagic
    case invalidManifestLength(UInt64)
    case invalidRelativePath(String)
    case fileOutsideRoot(String)
    case missingPayload(String)
    case payloadByteCountMismatch(path: String, expected: Int64, actual: Int64)
    case payloadHashMismatch(path: String, expected: String, actual: String)
    case payloadOrderMismatch
    case unexpectedTrailingData
    case invalidPayloadRole(String)
    case missingSQLitePayload
    case assetManifestMismatch
    case currentSummaryUnavailable
    case cleanupFailed(originalError: String, cleanupError: String)
}

struct BackupPackageManifest: Codable, Sendable, Equatable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let packageID: UUID
    let createdAt: Date
    let sourceAppVersion: String
    let sourceSchemaVersion: Int
    let sourceLibraryID: UUID
    let restoreSemantics: BackupPackageRestoreSemantics
    let payloads: [BackupPackagePayload]
}

struct BackupPackageRestoreSemantics: Codable, Sendable, Equatable {
    let mode: String
    let recordCount: Int
    let usedTagCount: Int
    let assetCount: Int
}

struct BackupPackagePayload: Codable, Sendable, Equatable {
    let role: BackupPackagePayloadRole
    let relativePath: String
    let byteCount: Int64
    let sha256: String
    let assetID: UUID?
    let contentHash: String?
}

enum BackupPackagePayloadRole: String, Codable, Sendable, Equatable {
    case sqlite
    case assetBlob
}

extension BackupRecoveryCounts {
    init(restoreSemantics: BackupPackageRestoreSemantics) {
        self.init(
            recordCount: restoreSemantics.recordCount,
            usedTagCount: restoreSemantics.usedTagCount,
            assetCount: restoreSemantics.assetCount
        )
    }
}
