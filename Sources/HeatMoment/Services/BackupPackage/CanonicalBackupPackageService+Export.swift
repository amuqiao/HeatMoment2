import Foundation
import GRDB

extension CanonicalBackupPackageService {
    func prepareExportPackageWithoutGate(
        descriptor: CanonicalStoreDescriptor,
        createdAt: Date
    ) throws -> BackupPackagePreparedExport {
        try discardAbandonedPreparedExports(descriptor: descriptor)
        let workspace = try createExportWorkspace(
            descriptor: descriptor,
            packageID: UUID()
        )
        let preparedDirectory = preparedExportDirectory(
            descriptor: descriptor,
            packageID: workspace.packageID
        )
        defer {
            if FileManager.default.fileExists(atPath: workspace.stagingDirectory.path) {
                try? FileManager.default.removeItem(at: workspace.stagingDirectory)
            }
        }

        try runtime.store.backup(to: workspace.snapshotURL)
        let catalog = try makeCatalog(fromSnapshotAt: workspace.snapshotURL)
        let manifest = try makeManifest(
            packageID: workspace.packageID,
            createdAt: createdAt,
            catalog: catalog,
            payloadRootDirectory: workspace.payloadRootDirectory
        )
        let destinationURL = exportPackageURL(
            preparedDirectory: preparedDirectory,
            packageID: workspace.packageID,
            createdAt: createdAt
        )
        return try writePinnedPreparedExportPackage(
            manifest: manifest,
            catalog: catalog,
            workspace: workspace,
            preparedDirectory: preparedDirectory,
            destinationURL: destinationURL
        )
    }

    func completePreparedExportWithoutGate(
        _ preparedExport: BackupPackagePreparedExport,
        completedAt: Date
    ) throws -> BackupPackageExportCompletion {
        guard FileManager.default.fileExists(atPath: preparedExport.fileURL.path) else {
            throw BackupPackageError.missingPreparedExportPackage(preparedExport.fileURL.path)
        }
        let packageData = try Data(contentsOf: preparedExport.fileURL)
        guard Int64(packageData.count) == preparedExport.byteCount else {
            throw BackupPackageError.payloadByteCountMismatch(
                path: preparedExport.fileURL.lastPathComponent,
                expected: preparedExport.byteCount,
                actual: Int64(packageData.count)
            )
        }
        let actualSHA256 = FileAssetStore.sha256Hex(packageData)
        guard actualSHA256 == preparedExport.sha256 else {
            throw BackupPackageError.payloadHashMismatch(
                path: preparedExport.fileURL.lastPathComponent,
                expected: preparedExport.sha256,
                actual: actualSHA256
            )
        }

        exportHistoryStore.recordExported(at: completedAt)
        do {
            try removePreparedExportDirectoryIfExists(preparedExport.preparedDirectory)
            return BackupPackageExportCompletion(
                packageID: preparedExport.packageID,
                exportedAt: completedAt,
                cleanupStatus: .completed
            )
        } catch {
            return BackupPackageExportCompletion(
                packageID: preparedExport.packageID,
                exportedAt: completedAt,
                cleanupStatus: .failedAfterExportRecorded(String(describing: error))
            )
        }
    }

    func createExportWorkspace(
        descriptor: CanonicalStoreDescriptor,
        packageID: UUID
    ) throws -> ExportWorkspace {
        let fileManager = FileManager.default
        let stagingDirectory = exportStagingDirectory(
            descriptor: descriptor,
            packageID: packageID
        )
        let payloadRootDirectory = stagingDirectory.appendingPathComponent(
            "Payload",
            isDirectory: true
        )
        let snapshotURL = payloadRootDirectory.appendingPathComponent(
            CanonicalRecoveryPointSnapshotService.snapshotFileName
        )
        if fileManager.fileExists(atPath: stagingDirectory.path) {
            try fileManager.removeItem(at: stagingDirectory)
        }
        try fileManager.createDirectory(
            at: payloadRootDirectory,
            withIntermediateDirectories: true
        )
        return ExportWorkspace(
            packageID: packageID,
            stagingDirectory: stagingDirectory,
            payloadRootDirectory: payloadRootDirectory,
            snapshotURL: snapshotURL
        )
    }

    func makeManifest(
        packageID: UUID,
        createdAt: Date,
        catalog: Catalog,
        payloadRootDirectory: URL
    ) throws -> BackupPackageManifest {
        let sqlitePayload = try makeSQLitePayload(
            snapshotURL: payloadRootDirectory.appendingPathComponent(
                CanonicalRecoveryPointSnapshotService.snapshotFileName
            ),
            rootDirectory: payloadRootDirectory
        )
        let assetPayloads = try copyAssetPayloads(
            assets: catalog.assets,
            to: payloadRootDirectory
        )
        return BackupPackageManifest(
            formatVersion: BackupPackageManifest.currentFormatVersion,
            packageID: packageID,
            createdAt: createdAt,
            sourceAppVersion: appVersion,
            sourceSchemaVersion: catalog.schemaVersion,
            sourceLibraryID: catalog.sourceLibraryID,
            restoreSemantics: BackupPackageRestoreSemantics(
                mode: "fullReplacement",
                recordCount: catalog.counts.recordCount,
                usedTagCount: catalog.counts.usedTagCount,
                assetCount: catalog.counts.assetCount
            ),
            payloads: [sqlitePayload] + assetPayloads
        )
    }

    func writePinnedPreparedExportPackage(
        manifest: BackupPackageManifest,
        catalog: Catalog,
        workspace: ExportWorkspace,
        preparedDirectory: URL,
        destinationURL: URL
    ) throws -> BackupPackagePreparedExport {
        try runtime.assetPinStore.pinContentHashes(
            catalog.assets.map(\.contentHash),
            ownerKind: .exportJob,
            ownerID: workspace.packageID.uuidString,
            createdAt: manifest.createdAt
        )
        do {
            try BackupPackageArchive.write(
                manifest: manifest,
                payloadRootDirectory: workspace.payloadRootDirectory,
                to: destinationURL
            )
            try runtime.assetPinStore.releasePins(
                ownerKind: .exportJob,
                ownerID: workspace.packageID.uuidString
            )
            let packageData = try Data(contentsOf: destinationURL)
            return BackupPackagePreparedExport(
                packageID: workspace.packageID,
                createdAt: manifest.createdAt,
                fileURL: destinationURL,
                preparedDirectory: preparedDirectory,
                byteCount: Int64(packageData.count),
                sha256: FileAssetStore.sha256Hex(packageData),
                counts: BackupRecoveryCounts(counts: catalog.counts)
            )
        } catch {
            try runtime.assetPinStore.releasePins(
                ownerKind: .exportJob,
                ownerID: workspace.packageID.uuidString
            )
            throw error
        }
    }

    func makeCatalog(fromSnapshotAt snapshotURL: URL) throws -> Catalog {
        let snapshotQueue = try DatabaseQueue(path: snapshotURL.path)
        return try snapshotQueue.read { db in
            let metadata = try fetchLibraryMetadata(in: db)
            let assets = try fetchCatalogAssets(in: db)
            return Catalog(
                sourceLibraryID: try metadata.canonicalUUID("library_id"),
                schemaVersion: metadata["schema_version"],
                counts: try Self.counts(in: db, assetCount: assets.count),
                assets: assets
            )
        }
    }

    static func counts(
        in db: Database,
        assetCount: Int? = nil
    ) throws -> CanonicalRecoveryPointCounts {
        let recordCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM moment_record") ?? 0
        let usedTagCount =
            try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT tag_id) FROM moment_tag_link") ?? 0
        let resolvedAssetCount: Int
        if let assetCount {
            resolvedAssetCount = assetCount
        } else {
            resolvedAssetCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM asset_record") ?? 0
        }
        return CanonicalRecoveryPointCounts(
            recordCount: recordCount,
            usedTagCount: usedTagCount,
            assetCount: resolvedAssetCount
        )
    }

    func makeSQLitePayload(
        snapshotURL: URL,
        rootDirectory: URL
    ) throws -> BackupPackagePayload {
        let data = try Data(contentsOf: snapshotURL)
        return BackupPackagePayload(
            role: .sqlite,
            relativePath: try relativePath(for: snapshotURL, rootDirectory: rootDirectory),
            byteCount: Int64(data.count),
            sha256: FileAssetStore.sha256Hex(data),
            assetID: nil,
            contentHash: nil
        )
    }

    func copyAssetPayloads(
        assets: [CatalogAsset],
        to payloadRootDirectory: URL
    ) throws -> [BackupPackagePayload] {
        try assets.map { asset in
            let storedAsset = try runtime.assetStore.validateStoredAsset(
                forContentHash: asset.contentHash
            )
            guard Int64(storedAsset.byteCount) == asset.byteCount else {
                throw BackupPackageError.payloadByteCountMismatch(
                    path: asset.contentHash,
                    expected: asset.byteCount,
                    actual: Int64(storedAsset.byteCount)
                )
            }
            let destinationURL = assetPayloadDestinationURL(
                asset: asset,
                payloadRootDirectory: payloadRootDirectory
            )
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: storedAsset.fileURL, to: destinationURL)
            let data = try Data(contentsOf: destinationURL)
            return BackupPackagePayload(
                role: .assetBlob,
                relativePath: try relativePath(
                    for: destinationURL,
                    rootDirectory: payloadRootDirectory
                ),
                byteCount: Int64(data.count),
                sha256: FileAssetStore.sha256Hex(data),
                assetID: asset.assetID,
                contentHash: asset.contentHash
            )
        }
    }

    func assetPayloadDestinationURL(
        asset: CatalogAsset,
        payloadRootDirectory: URL
    ) -> URL {
        payloadRootDirectory
            .appendingPathComponent("Assets", isDirectory: true)
            .appendingPathComponent("blobs", isDirectory: true)
            .appendingPathComponent(String(asset.contentHash.prefix(2)), isDirectory: true)
            .appendingPathComponent(asset.contentHash)
    }

    func fetchLibraryMetadata(in db: Database) throws -> Row {
        guard
            let metadata = try Row.fetchOne(
                db,
                sql: """
                    SELECT library_id, schema_version
                    FROM library_metadata
                    WHERE id = 1
                    """
            )
        else {
            throw DatabaseError(message: "Missing canonical library metadata")
        }
        return metadata
    }

    func fetchCatalogAssets(in db: Database) throws -> [CatalogAsset] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT id, content_hash, byte_count
                FROM asset_record
                ORDER BY id ASC
                """
        )
        .map { row in
            CatalogAsset(
                assetID: try row.canonicalUUID("id"),
                contentHash: row["content_hash"],
                byteCount: row["byte_count"]
            )
        }
    }
}
