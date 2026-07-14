import Foundation

extension CanonicalBackupPackageService {
    func prepareImportWithoutGate(
        _ preview: BackupPackagePreview,
        descriptor: CanonicalStoreDescriptor,
        now: Date
    ) throws -> BackupPackagePreparedImport {
        let executor = try CanonicalRestoreExecutor(runtime: runtime)
        var importedAssets: ImportedAssets?
        var restoreSafetyIDToCleanUp: UUID?
        var didArmPendingRestore = false
        do {
            let extractedDirectory = preview.stagingDirectory.appendingPathComponent(
                "Extracted",
                isDirectory: true
            )
            try validatePackageReadyForImport(
                preview.manifest,
                extractedDirectory: extractedDirectory
            )
            let sqlitePayload = try sqlitePayload(in: preview.manifest)
            let snapshotURL = try BackupPackageArchive.absoluteURL(
                forRelativePath: sqlitePayload.relativePath,
                rootDirectory: extractedDirectory
            )
            let imported = try importAssetPayloads(
                from: extractedDirectory,
                manifest: preview.manifest,
                descriptor: descriptor
            )
            importedAssets = imported
            let pendingContext = try stagePendingRestore(
                executor: executor,
                preview: preview,
                snapshotURL: snapshotURL,
                importedAssets: imported,
                now: now
            )
            let restoreSafety = try createRestoreSafetyPoint(now: now)
            restoreSafetyIDToCleanUp = restoreSafety.id
            let armedRestore = try armImportedRestore(
                executor: executor,
                preview: preview,
                pendingContext: pendingContext,
                restoreSafety: restoreSafety
            )
            didArmPendingRestore = true
            return armedRestore
        } catch {
            try cleanUpPrepareImportIfNeeded(
                ImportCleanupContext(
                    didArmPendingRestore: didArmPendingRestore,
                    executor: executor,
                    restoreSafetyID: restoreSafetyIDToCleanUp,
                    importedAssets: importedAssets,
                    stagingDirectory: preview.stagingDirectory,
                    originalError: error
                )
            )
            throw error
        }
    }

    func cleanUpPrepareImportIfNeeded(_ context: ImportCleanupContext) throws {
        guard !context.didArmPendingRestore else {
            return
        }
        try cleanUpFailedPrepareImport(
            executor: context.executor,
            restoreSafetyID: context.restoreSafetyID,
            importedAssets: context.importedAssets,
            stagingDirectory: context.stagingDirectory,
            originalError: context.originalError
        )
    }

    func validatePackageReadyForImport(
        _ manifest: BackupPackageManifest,
        extractedDirectory: URL
    ) throws {
        try validateManifest(manifest)
        try BackupPackageArchive.validatePayloads(in: extractedDirectory, manifest: manifest)
        try validateExtractedPackage(manifest: manifest, extractedDirectory: extractedDirectory)
    }

    func stagePendingRestore(
        executor: CanonicalRestoreExecutor,
        preview: BackupPackagePreview,
        snapshotURL: URL,
        importedAssets: ImportedAssets,
        now: Date
    ) throws -> CanonicalPendingRestoreContext {
        let counts = CanonicalPendingRestoreCounts(
            recordCount: preview.counts.recordCount,
            usedTagCount: preview.counts.usedTagCount,
            assetCount: preview.counts.assetCount
        )
        return try executor.stageImportedSnapshot(
            CanonicalImportedSnapshotRestoreRequest(
                snapshotURL: snapshotURL,
                packageID: preview.id,
                packageCreatedAt: preview.createdAt,
                schemaVersion: preview.sourceSchemaVersion,
                appVersion: preview.sourceAppVersion,
                counts: counts,
                assetManifest: importedAssets.manifest,
                restoreJobID: UUID(),
                restoredSyncEpoch: UUID(),
                now: now
            )
        )
    }

    func armImportedRestore(
        executor: CanonicalRestoreExecutor,
        preview: BackupPackagePreview,
        pendingContext: CanonicalPendingRestoreContext,
        restoreSafety: CanonicalRecoveryPointRecord
    ) throws -> BackupPackagePreparedImport {
        var pendingContext = pendingContext
        pendingContext.restoreSafetyRecoveryPoint = restoreSafety
        pendingContext.restoreSafetyAssetManifest =
            try runtime.recoveryPointStore.assetManifest(for: restoreSafety.id)
        try executor.updateStagedRestoreContext(context: pendingContext)
        try removeImportStagingDirectory(preview.stagingDirectory)
        try executor.armStagedRestore(context: pendingContext)
        return BackupPackagePreparedImport(
            pendingContext: BackupPendingRestoreContext(context: pendingContext),
            packageID: preview.id,
            packageCreatedAt: preview.createdAt,
            retentionStatus: enforceRetentionAfterRestoreIsArmed()
        )
    }

    func createRestoreSafetyPoint(now: Date) throws -> CanonicalRecoveryPointRecord {
        try runtime.recoveryPointSnapshotService.createRecoveryPoint(
            RecoveryPointSnapshotRequest(
                id: UUID(),
                reason: .restoreSafety,
                createdAt: now,
                appVersion: appVersion
            ),
            enforcesRetention: false
        )
        .recoveryPoint
    }

    func enforceRetentionAfterRestoreIsArmed() -> BackupPackageRestoreRetentionStatus {
        do {
            _ = try enforceRecoveryPointRetention(runtime)
            return .completed
        } catch {
            return .failedAfterRestoreArmed(String(describing: error))
        }
    }

    func validateManifest(_ manifest: BackupPackageManifest) throws {
        guard manifest.formatVersion == BackupPackageManifest.currentFormatVersion else {
            throw BackupPackageError.unsupportedFormatVersion(manifest.formatVersion)
        }
        guard manifest.sourceSchemaVersion == CanonicalStore.currentSchemaVersion else {
            throw BackupPackageError.unsupportedSchemaVersion(
                expected: CanonicalStore.currentSchemaVersion,
                actual: manifest.sourceSchemaVersion
            )
        }
        guard manifest.restoreSemantics.mode == "fullReplacement" else {
            throw BackupPackageError.invalidPayloadRole(manifest.restoreSemantics.mode)
        }
        let sqlitePayloads = manifest.payloads.filter { $0.role == .sqlite }
        guard sqlitePayloads.count == 1 else {
            throw BackupPackageError.missingSQLitePayload
        }
        let assetPayloads = manifest.payloads.filter { $0.role == .assetBlob }
        guard assetPayloads.count == manifest.restoreSemantics.assetCount else {
            throw BackupPackageError.assetManifestMismatch
        }
        for payload in manifest.payloads {
            switch payload.role {
            case .sqlite:
                guard payload.assetID == nil, payload.contentHash == nil else {
                    throw BackupPackageError.invalidPayloadRole(payload.role.rawValue)
                }
            case .assetBlob:
                guard payload.assetID != nil,
                    let contentHash = payload.contentHash,
                    FileAssetStore.isValidContentHash(contentHash)
                else {
                    throw BackupPackageError.invalidPayloadRole(payload.role.rawValue)
                }
            }
        }
    }

    func validateExtractedPackage(
        manifest: BackupPackageManifest,
        extractedDirectory: URL
    ) throws {
        let sqlitePayload = try sqlitePayload(in: manifest)
        let sqliteURL = try BackupPackageArchive.absoluteURL(
            forRelativePath: sqlitePayload.relativePath,
            rootDirectory: extractedDirectory
        )
        let catalog = try makeCatalog(fromSnapshotAt: sqliteURL)
        guard catalog.sourceLibraryID == manifest.sourceLibraryID,
            catalog.schemaVersion == manifest.sourceSchemaVersion,
            catalog.counts.recordCount == manifest.restoreSemantics.recordCount,
            catalog.counts.usedTagCount == manifest.restoreSemantics.usedTagCount,
            catalog.counts.assetCount == manifest.restoreSemantics.assetCount
        else {
            throw BackupPackageError.assetManifestMismatch
        }
        try validateCatalogAssets(catalog.assets, manifest: manifest)
    }

    func validateCatalogAssets(
        _ assets: [CatalogAsset],
        manifest: BackupPackageManifest
    ) throws {
        var payloadsByAssetID: [UUID: BackupPackagePayload] = [:]
        for payload in manifest.payloads where payload.role == .assetBlob {
            guard let assetID = payload.assetID else {
                throw BackupPackageError.invalidPayloadRole(payload.role.rawValue)
            }
            guard payloadsByAssetID[assetID] == nil else {
                throw BackupPackageError.assetManifestMismatch
            }
            payloadsByAssetID[assetID] = payload
        }
        guard payloadsByAssetID.count == assets.count else {
            throw BackupPackageError.assetManifestMismatch
        }
        for asset in assets {
            guard let payload = payloadsByAssetID[asset.assetID],
                payload.contentHash == asset.contentHash,
                payload.byteCount == asset.byteCount
            else {
                throw BackupPackageError.assetManifestMismatch
            }
        }
    }

    func importAssetPayloads(
        from extractedDirectory: URL,
        manifest: BackupPackageManifest,
        descriptor: CanonicalStoreDescriptor
    ) throws -> ImportedAssets {
        var pendingAssets: [CanonicalPendingRestoreAsset] = []
        var storedAssets: [StoredFileAsset] = []
        do {
            for payload in sortedAssetPayloads(in: manifest) {
                let importedAsset = try importAssetPayload(
                    payload,
                    extractedDirectory: extractedDirectory,
                    descriptor: descriptor
                )
                storedAssets.append(importedAsset.storedAsset)
                pendingAssets.append(importedAsset.pendingAsset)
            }
            return ImportedAssets(manifest: pendingAssets, storedAssets: storedAssets)
        } catch {
            do {
                try cleanUpImportedAssets(storedAssets)
            } catch let cleanupError {
                throw BackupPackageError.cleanupFailed(
                    originalError: String(describing: error),
                    cleanupError: String(describing: cleanupError)
                )
            }
            throw error
        }
    }

    func sortedAssetPayloads(in manifest: BackupPackageManifest) -> [BackupPackagePayload] {
        manifest.payloads
            .filter { $0.role == .assetBlob }
            .sorted { lhs, rhs in
                (lhs.assetID?.uuidString ?? "") < (rhs.assetID?.uuidString ?? "")
            }
    }

    func importAssetPayload(
        _ payload: BackupPackagePayload,
        extractedDirectory: URL,
        descriptor: CanonicalStoreDescriptor
    ) throws -> (pendingAsset: CanonicalPendingRestoreAsset, storedAsset: StoredFileAsset) {
        guard let assetID = payload.assetID,
            let contentHash = payload.contentHash
        else {
            throw BackupPackageError.invalidPayloadRole(payload.role.rawValue)
        }
        let payloadURL = try BackupPackageArchive.absoluteURL(
            forRelativePath: payload.relativePath,
            rootDirectory: extractedDirectory
        )
        let storedAsset = try runtime.assetStore.store(
            data: try Data(contentsOf: payloadURL),
            expectedContentHash: contentHash
        )
        guard Int64(storedAsset.byteCount) == payload.byteCount else {
            throw BackupPackageError.payloadByteCountMismatch(
                path: payload.relativePath,
                expected: payload.byteCount,
                actual: Int64(storedAsset.byteCount)
            )
        }
        let pendingAsset = try CanonicalPendingRestoreAsset(
            assetID: assetID,
            contentHash: contentHash,
            byteCount: payload.byteCount,
            relativePath: relativePath(
                for: storedAsset.fileURL,
                rootDirectory: descriptor.rootDirectory
            )
        )
        return (pendingAsset, storedAsset)
    }

    func sqlitePayload(in manifest: BackupPackageManifest) throws -> BackupPackagePayload {
        guard let payload = manifest.payloads.first(where: { $0.role == .sqlite }) else {
            throw BackupPackageError.missingSQLitePayload
        }
        return payload
    }

    func cleanUpFailedPrepareImport(
        executor: CanonicalRestoreExecutor,
        restoreSafetyID: UUID?,
        importedAssets: ImportedAssets?,
        stagingDirectory: URL,
        originalError: Error
    ) throws {
        var cleanupErrors: [String] = []
        do {
            try executor.clearPendingRestore()
        } catch {
            cleanupErrors.append(String(describing: error))
        }
        if let restoreSafetyID {
            do {
                try runtime.recoveryPointSnapshotService.deleteRecoveryPoint(
                    id: restoreSafetyID
                )
            } catch {
                cleanupErrors.append(String(describing: error))
            }
        }
        if let importedAssets {
            do {
                try cleanUpImportedAssets(importedAssets.storedAssets)
            } catch {
                cleanupErrors.append(String(describing: error))
            }
        }
        do {
            try removeDirectoryIfExists(stagingDirectory)
        } catch {
            cleanupErrors.append(String(describing: error))
        }
        guard cleanupErrors.isEmpty else {
            throw BackupPackageError.cleanupFailed(
                originalError: "cleanup imported assets",
                cleanupError: cleanupErrors.joined(separator: "; ")
            )
        }
    }

    func cleanUpImportedAssets(_ storedAssets: [StoredFileAsset]) throws {
        var cleanupErrors: [String] = []
        for storedAsset in storedAssets {
            do {
                try runtime.assetStore.removeStoredAsset(storedAsset)
            } catch {
                cleanupErrors.append(String(describing: error))
            }
        }
        guard cleanupErrors.isEmpty else {
            throw BackupPackageError.cleanupFailed(
                originalError: "cleanup imported assets",
                cleanupError: cleanupErrors.joined(separator: "; ")
            )
        }
    }
}
