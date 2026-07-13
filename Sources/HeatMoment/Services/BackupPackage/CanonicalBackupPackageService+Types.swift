import Foundation

extension CanonicalBackupPackageService {
    struct CatalogAsset: Sendable, Equatable {
        let assetID: UUID
        let contentHash: String
        let byteCount: Int64
    }

    struct Catalog: Sendable, Equatable {
        let sourceLibraryID: UUID
        let schemaVersion: Int
        let counts: CanonicalRecoveryPointCounts
        let assets: [CatalogAsset]
    }

    struct ImportedAssets: Sendable, Equatable {
        let manifest: [CanonicalPendingRestoreAsset]
        let storedAssets: [StoredFileAsset]
    }

    struct ExportWorkspace: Sendable, Equatable {
        let packageID: UUID
        let stagingDirectory: URL
        let payloadRootDirectory: URL
        let snapshotURL: URL
    }

    struct ImportCleanupContext {
        let didArmPendingRestore: Bool
        let executor: CanonicalRestoreExecutor
        let restoreSafetyID: UUID?
        let importedAssets: ImportedAssets?
        let stagingDirectory: URL
        let originalError: Error
    }
}
