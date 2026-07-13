import Foundation
import GRDB

struct CanonicalRestoreExecutor: Sendable {
    private static let armedFileName = "armed"
    private static let contextFileName = "context.json"
    private static let payloadDirectoryName = "payload"

    let descriptor: CanonicalStoreDescriptor
    let store: CanonicalStore
    let recoveryPointStore: CanonicalRecoveryPointStore
    let snapshotService: CanonicalRecoveryPointSnapshotService
    let assetPinStore: CanonicalAssetPinStore
    let operationGate: CanonicalAssetOperationGate

    init(runtime: CanonicalLibraryRuntime) throws {
        guard let descriptor = runtime.descriptor else {
            throw CanonicalRestoreExecutorError.runtimeRequiresDescriptor
        }
        self.descriptor = descriptor
        store = runtime.store
        recoveryPointStore = runtime.recoveryPointStore
        snapshotService = runtime.recoveryPointSnapshotService
        assetPinStore = runtime.assetPinStore
        operationGate = runtime.assetOperationGate
    }

    @discardableResult
    func stageRestore(
        recoveryPointID: UUID,
        restoreJobID: UUID = UUID(),
        restoredSyncEpoch: UUID = UUID(),
        now: Date = .now
    ) throws -> CanonicalPendingRestoreContext {
        try operationGate.performSync {
            try stageRestoreWithoutGate(
                recoveryPointID: recoveryPointID,
                restoreJobID: restoreJobID,
                restoredSyncEpoch: restoredSyncEpoch,
                now: now
            )
        }
    }

    func armStagedRestore(
        context expectedContext: CanonicalPendingRestoreContext
    ) throws {
        try operationGate.performSync {
            let context = try Self.readContext(in: descriptor.pendingRestoreDirectory)
            guard context == expectedContext else {
                throw CanonicalRestoreExecutorError.pendingContextMismatch
            }
            try Self.validatePendingPayload(context: context, descriptor: descriptor)
            try Data(context.restoreJobID.uuidString.utf8).write(
                to: descriptor.pendingRestoreDirectory.appendingPathComponent(Self.armedFileName),
                options: [.atomic]
            )
        }
    }

    func updateStagedRestoreContext(
        context: CanonicalPendingRestoreContext
    ) throws {
        try operationGate.performSync {
            try Self.validatePendingPayload(context: context, descriptor: descriptor)
            try Self.writeContext(
                context,
                to: descriptor.pendingRestoreDirectory.appendingPathComponent(Self.contextFileName)
            )
        }
    }

    func clearPendingRestore() throws {
        try operationGate.performSync {
            try Self.clearPendingRestore(
                descriptor: descriptor,
                assetPinStore: assetPinStore
            )
        }
    }

    static func performPendingRestoreIfNeeded(
        descriptor: CanonicalStoreDescriptor,
        now: Date = .now
    ) throws -> CanonicalBootRestoreResult {
        try performPendingRestoreIfNeeded(
            descriptor: descriptor,
            now: now,
            replaceStorePayload: { payloadDirectory, descriptor in
                try replaceStorePayload(from: payloadDirectory, descriptor: descriptor)
            }
        )
    }

    static func performPendingRestoreIfNeeded(
        descriptor: CanonicalStoreDescriptor,
        now: Date = .now,
        replaceStorePayload: (URL, CanonicalStoreDescriptor) throws -> Void
    ) throws -> CanonicalBootRestoreResult {
        let pendingDirectory = descriptor.pendingRestoreDirectory
        guard FileManager.default.fileExists(atPath: pendingDirectory.path) else {
            return .none
        }

        let armedURL = pendingDirectory.appendingPathComponent(armedFileName)
        guard FileManager.default.fileExists(atPath: armedURL.path) else {
            try clearPendingRestore(descriptor: descriptor)
            return .none
        }

        var pendingContext: CanonicalPendingRestoreContext?
        do {
            let context = try readContext(in: pendingDirectory)
            pendingContext = context
            let armedData = try Data(contentsOf: armedURL)
            guard let armedRestoreJobID = String(data: armedData, encoding: .utf8) else {
                throw CanonicalRestoreExecutorError.invalidArmedMarkerEncoding
            }
            guard armedRestoreJobID == context.restoreJobID.uuidString else {
                throw CanonicalRestoreExecutorError.armedMarkerMismatch(
                    expected: context.restoreJobID.uuidString,
                    actual: armedRestoreJobID
                )
            }

            try validatePendingPayload(context: context, descriptor: descriptor)
            try prepareIncomingSnapshot(context: context, descriptor: descriptor, now: now)
            try replaceStorePayload(payloadDirectory(in: pendingDirectory), descriptor)
            try FileManager.default.removeItem(at: pendingDirectory)
            return .restored(context)
        } catch let error as CanonicalRestoreCriticalError {
            throw error
        } catch let restoreError {
            do {
                try clearPendingRestore(descriptor: descriptor)
            } catch let cleanupError {
                return .failed(
                    CanonicalBootRestoreFailure(
                        underlying: CanonicalRestoreExecutorError.cleanupFailed(
                            originalError: String(describing: restoreError),
                            cleanupError: String(describing: cleanupError)
                        ),
                        context: pendingContext
                    )
                )
            }
            return .failed(
                CanonicalBootRestoreFailure(underlying: restoreError, context: pendingContext))
        }
    }

    static func replaceStorePayload(
        from payloadDirectory: URL,
        descriptor: CanonicalStoreDescriptor
    ) throws {
        try replaceStorePayload(
            from: payloadDirectory,
            descriptor: descriptor,
            copyIncomingPayload: { payloadDirectory, descriptor in
                try Self.copyIncomingPayload(from: payloadDirectory, descriptor: descriptor)
            }
        )
    }

    static func replaceStorePayload(
        from payloadDirectory: URL,
        descriptor: CanonicalStoreDescriptor,
        copyIncomingPayload: (URL, CanonicalStoreDescriptor) throws -> Void
    ) throws {
        func defaultRollbackStorePayload(
            _ movedCurrentPayload: [URL],
            _ rollbackDirectory: URL,
            _ removesRootPayloadBeforeRollback: Bool,
            _ descriptor: CanonicalStoreDescriptor
        ) throws {
            try Self.rollbackStorePayload(
                movedCurrentPayload: movedCurrentPayload,
                rollbackDirectory: rollbackDirectory,
                removesRootPayloadBeforeRollback: removesRootPayloadBeforeRollback,
                descriptor: descriptor
            )
        }

        try replaceStorePayload(
            from: payloadDirectory,
            descriptor: descriptor,
            copyIncomingPayload: copyIncomingPayload,
            rollbackStorePayload: defaultRollbackStorePayload
        )
    }

    static func replaceStorePayload(
        from payloadDirectory: URL,
        descriptor: CanonicalStoreDescriptor,
        copyIncomingPayload: (URL, CanonicalStoreDescriptor) throws -> Void,
        rollbackStorePayload: ([URL], URL, Bool, CanonicalStoreDescriptor) throws -> Void
    ) throws {
        try FileManager.default.createDirectory(
            at: descriptor.rootDirectory,
            withIntermediateDirectories: true
        )
        let rollbackDirectory = descriptor.rootDirectory.appendingPathComponent(
            "RestoreRollback-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: rollbackDirectory,
            withIntermediateDirectories: true
        )

        var movedCurrentPayload: [URL] = []
        var didMoveAllCurrentPayload = false
        do {
            movedCurrentPayload = try moveCurrentPayload(
                to: rollbackDirectory,
                descriptor: descriptor
            )
            didMoveAllCurrentPayload = true
            try copyIncomingPayload(payloadDirectory, descriptor)
            try FileManager.default.removeItem(at: rollbackDirectory)
        } catch {
            do {
                try rollbackStorePayload(
                    movedCurrentPayload,
                    rollbackDirectory,
                    didMoveAllCurrentPayload,
                    descriptor
                )
            } catch {
                throw CanonicalRestoreCriticalError.rollbackFailed(error)
            }
            throw error
        }
    }
}

private extension CanonicalRestoreExecutor {
    func stageRestoreWithoutGate(
        recoveryPointID: UUID,
        restoreJobID: UUID,
        restoredSyncEpoch: UUID,
        now: Date
    ) throws -> CanonicalPendingRestoreContext {
        let recoveryPoint = try snapshotService.validateRecoveryPoint(id: recoveryPointID)
        guard recoveryPoint.status == .available else {
            throw CanonicalRestoreExecutorError.recoveryPointUnavailable(recoveryPointID)
        }

        let manifest = try recoveryPointStore.assetManifest(for: recoveryPointID)
        let metadata = try currentMetadata()
        let context = CanonicalPendingRestoreContext(
            restoreJobID: restoreJobID,
            selectedRecoveryPointID: recoveryPoint.id,
            selectedCreatedAt: recoveryPoint.createdAt,
            currentLibraryID: metadata.libraryID,
            currentDeviceID: metadata.deviceID,
            currentLibraryCreatedAt: metadata.createdAt,
            restoredSyncEpoch: restoredSyncEpoch,
            schemaVersion: recoveryPoint.schemaVersion,
            appVersion: recoveryPoint.appVersion,
            snapshot: CanonicalPendingRestoreSnapshot(
                relativePath: recoveryPoint.sqliteSnapshot.relativePath,
                byteCount: recoveryPoint.sqliteSnapshot.byteCount,
                sha256: recoveryPoint.sqliteSnapshot.sha256
            ),
            counts: CanonicalPendingRestoreCounts(
                recordCount: recoveryPoint.counts.recordCount,
                tagCount: recoveryPoint.counts.tagCount,
                assetCount: recoveryPoint.counts.assetCount
            ),
            assetManifest: manifest.map(CanonicalPendingRestoreAsset.init(record:))
        )

        do {
            try Self.clearPendingRestore(
                descriptor: descriptor,
                assetPinStore: assetPinStore
            )
            try Self.createStagedPayload(
                context: context,
                descriptor: descriptor
            )
            try assetPinStore.pinContentHashes(
                context.assetManifest.map(\.contentHash),
                ownerKind: .restoreStaging,
                ownerID: context.restoreJobID.uuidString,
                createdAt: now
            )
            return context
        } catch let stageError {
            do {
                try Self.clearPendingRestore(
                    descriptor: descriptor,
                    assetPinStore: assetPinStore
                )
            } catch let cleanupError {
                throw CanonicalRestoreExecutorError.cleanupFailed(
                    originalError: String(describing: stageError),
                    cleanupError: String(describing: cleanupError)
                )
            }
            throw stageError
        }
    }

    func currentMetadata() throws -> CanonicalLibraryMetadata {
        try store.read { db in
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

    static func createStagedPayload(
        context: CanonicalPendingRestoreContext,
        descriptor: CanonicalStoreDescriptor
    ) throws {
        let pendingDirectory = descriptor.pendingRestoreDirectory
        let payloadDirectory = payloadDirectory(in: pendingDirectory)
        try FileManager.default.createDirectory(
            at: payloadDirectory,
            withIntermediateDirectories: true
        )

        let snapshotURL = try absoluteURL(
            forRelativePath: context.snapshot.relativePath,
            rootDirectory: descriptor.rootDirectory
        )
        try FileManager.default.copyItem(
            at: snapshotURL,
            to: payloadDatabaseURL(in: pendingDirectory, descriptor: descriptor)
        )
        try writeContext(context, to: pendingDirectory.appendingPathComponent(contextFileName))
        try validatePendingPayload(context: context, descriptor: descriptor)
    }

    static func prepareIncomingSnapshot(
        context: CanonicalPendingRestoreContext,
        descriptor: CanonicalStoreDescriptor,
        now: Date
    ) throws {
        let queue = try DatabaseQueue(
            path: payloadDatabaseURL(
                in: descriptor.pendingRestoreDirectory,
                descriptor: descriptor
            ).path)
        try queue.write { db in
            try db.execute(
                sql: """
                    UPDATE library_metadata
                    SET library_id = ?,
                        device_id = ?,
                        sync_epoch = ?,
                        created_at = ?,
                        updated_at = ?
                    WHERE id = 1
                    """,
                arguments: [
                    context.currentLibraryID.uuidString,
                    context.currentDeviceID.uuidString,
                    context.restoredSyncEpoch.uuidString,
                    context.currentLibraryCreatedAt.timeIntervalSince1970,
                    now.timeIntervalSince1970,
                ]
            )
            try pruneRecoveryPointsWithMissingSnapshots(
                db: db,
                rootDirectory: descriptor.rootDirectory
            )
            if let restoreSafety = context.restoreSafetyRecoveryPoint {
                try insertRestoreSafetyRecoveryPoint(
                    restoreSafety,
                    assetManifest: context.restoreSafetyAssetManifest,
                    db: db
                )
            }
            _ = try evictOverflowRecoveryPoints(db: db)
        }
    }

    static func pruneRecoveryPointsWithMissingSnapshots(
        db: Database,
        rootDirectory: URL
    ) throws {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT id, sqlite_snapshot_relative_path
                FROM recovery_point_record
                """
        )
        for row in rows {
            let id = try row.canonicalUUID("id")
            let relativePath: String = row["sqlite_snapshot_relative_path"]
            let snapshotURL = try absoluteURL(
                forRelativePath: relativePath,
                rootDirectory: rootDirectory
            )
            if !FileManager.default.fileExists(atPath: snapshotURL.path) {
                try deleteRecoveryPointCatalog(id: id, db: db)
            }
        }
    }

    static func evictOverflowRecoveryPoints(db: Database) throws -> [UUID] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT id
                FROM recovery_point_record
                ORDER BY created_at DESC, id DESC
                """
        )
        let evictedIDs = try rows.dropFirst(
            CanonicalRecoveryPointStore.retainedRecoveryPointLimit
        ).map { row in
            try row.canonicalUUID("id")
        }
        for id in evictedIDs {
            try deleteRecoveryPointCatalog(id: id, db: db)
        }
        return evictedIDs
    }

    static func deleteRecoveryPointCatalog(id: UUID, db: Database) throws {
        try db.execute(
            sql: """
                DELETE FROM asset_pin_record
                WHERE owner_kind = ? AND owner_id = ?
                """,
            arguments: [CanonicalAssetPinOwnerKind.recoveryPoint.rawValue, id.uuidString]
        )
        try db.execute(
            sql: "DELETE FROM recovery_point_asset_record WHERE recovery_point_id = ?",
            arguments: [id.uuidString]
        )
        try db.execute(
            sql: "DELETE FROM recovery_point_record WHERE id = ?",
            arguments: [id.uuidString]
        )
    }

    static func insertRestoreSafetyRecoveryPoint(
        _ record: CanonicalRecoveryPointRecord,
        assetManifest: [CanonicalRecoveryPointAssetRecord],
        db: Database
    ) throws {
        try db.execute(
            sql: "DELETE FROM recovery_point_asset_record WHERE recovery_point_id = ?",
            arguments: [record.id.uuidString]
        )
        try db.execute(
            sql: "DELETE FROM asset_pin_record WHERE owner_kind = ? AND owner_id = ?",
            arguments: [
                CanonicalAssetPinOwnerKind.recoveryPoint.rawValue,
                record.id.uuidString,
            ]
        )
        try db.execute(
            sql: """
                INSERT OR REPLACE INTO recovery_point_record (
                    id, created_at, reason, status, schema_version, app_version,
                    source_library_id, sqlite_snapshot_relative_path,
                    sqlite_snapshot_byte_count, sqlite_snapshot_sha256,
                    record_count, tag_count, asset_count
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                record.id.uuidString,
                record.createdAt.timeIntervalSince1970,
                record.reason.rawValue,
                record.status.rawValue,
                record.schemaVersion,
                record.appVersion,
                record.sourceLibraryID.uuidString,
                record.sqliteSnapshot.relativePath,
                record.sqliteSnapshot.byteCount,
                record.sqliteSnapshot.sha256,
                record.counts.recordCount,
                record.counts.tagCount,
                record.counts.assetCount,
            ]
        )
        for asset in assetManifest {
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO recovery_point_asset_record (
                        recovery_point_id, asset_id, content_hash, byte_count, relative_path
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    record.id.uuidString,
                    asset.assetID.uuidString,
                    asset.contentHash,
                    asset.byteCount,
                    asset.relativePath,
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO asset_pin_record (
                        id, content_hash, owner_kind, owner_id, created_at, expires_at
                    ) VALUES (?, ?, ?, ?, ?, NULL)
                    ON CONFLICT(content_hash, owner_kind, owner_id) DO UPDATE SET
                        created_at = excluded.created_at,
                        expires_at = NULL
                    """,
                arguments: [
                    UUID().uuidString,
                    asset.contentHash,
                    CanonicalAssetPinOwnerKind.recoveryPoint.rawValue,
                    record.id.uuidString,
                    record.createdAt.timeIntervalSince1970,
                ]
            )
        }
    }

    static func moveCurrentPayload(
        to rollbackDirectory: URL,
        descriptor: CanonicalStoreDescriptor
    ) throws -> [URL] {
        var movedCurrentPayload: [URL] = []
        for url in try descriptor.storePayloadURLs() {
            let rollbackURL = rollbackDirectory.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: rollbackURL)
            movedCurrentPayload.append(rollbackURL)
        }
        return movedCurrentPayload
    }

    static func copyIncomingPayload(
        from payloadDirectory: URL,
        descriptor: CanonicalStoreDescriptor
    ) throws {
        let incomingDatabaseURL = payloadDirectory.appendingPathComponent(
            descriptor.databaseURL.lastPathComponent
        )
        guard FileManager.default.fileExists(atPath: incomingDatabaseURL.path) else {
            throw CanonicalRestoreExecutorError.missingPayload(incomingDatabaseURL.path)
        }
        try FileManager.default.copyItem(at: incomingDatabaseURL, to: descriptor.databaseURL)
    }

    static func rollbackStorePayload(
        movedCurrentPayload: [URL],
        rollbackDirectory: URL,
        removesRootPayloadBeforeRollback: Bool,
        descriptor: CanonicalStoreDescriptor
    ) throws {
        if removesRootPayloadBeforeRollback {
            for url in try descriptor.storePayloadURLs() {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            }
        }
        for rollbackURL in movedCurrentPayload {
            let originalURL = descriptor.rootDirectory.appendingPathComponent(
                rollbackURL.lastPathComponent
            )
            if FileManager.default.fileExists(atPath: originalURL.path) {
                try FileManager.default.removeItem(at: originalURL)
            }
            try FileManager.default.moveItem(at: rollbackURL, to: originalURL)
        }
        if FileManager.default.fileExists(atPath: rollbackDirectory.path) {
            try FileManager.default.removeItem(at: rollbackDirectory)
        }
    }

    static func validatePendingPayload(
        context: CanonicalPendingRestoreContext,
        descriptor: CanonicalStoreDescriptor
    ) throws {
        let payloadURL = payloadDatabaseURL(
            in: descriptor.pendingRestoreDirectory,
            descriptor: descriptor
        )
        guard FileManager.default.fileExists(atPath: payloadURL.path) else {
            throw CanonicalRestoreExecutorError.missingPayload(payloadURL.path)
        }

        let actualByteCount = try fileSize(payloadURL)
        guard actualByteCount == context.snapshot.byteCount else {
            throw CanonicalRestoreExecutorError.snapshotByteCountMismatch(
                expected: context.snapshot.byteCount,
                actual: actualByteCount
            )
        }

        let actualHash = FileAssetStore.sha256Hex(try Data(contentsOf: payloadURL))
        guard actualHash == context.snapshot.sha256 else {
            throw CanonicalRestoreExecutorError.snapshotHashMismatch(
                expected: context.snapshot.sha256,
                actual: actualHash
            )
        }

        let snapshotCatalog = try makeCatalogInput(
            fromSnapshotAt: payloadURL,
            recoveryPointID: context.selectedRecoveryPointID,
            descriptor: descriptor
        )
        guard snapshotCatalog.schemaVersion == context.schemaVersion else {
            throw CanonicalRestoreExecutorError.snapshotSchemaVersionMismatch(
                expected: context.schemaVersion,
                actual: snapshotCatalog.schemaVersion
            )
        }
        let expectedCounts = CanonicalRecoveryPointCounts(
            recordCount: context.counts.recordCount,
            tagCount: context.counts.tagCount,
            assetCount: context.counts.assetCount
        )
        guard snapshotCatalog.counts == expectedCounts else {
            throw CanonicalRestoreExecutorError.catalogCountsMismatch(
                expected: expectedCounts,
                actual: snapshotCatalog.counts
            )
        }
        guard snapshotCatalog.assetManifest == context.assetManifest else {
            throw CanonicalRestoreExecutorError.assetManifestMismatch
        }
    }

    struct PendingCatalogInput {
        let schemaVersion: Int
        let counts: CanonicalRecoveryPointCounts
        let assetManifest: [CanonicalPendingRestoreAsset]
    }

    static func makeCatalogInput(
        fromSnapshotAt snapshotURL: URL,
        recoveryPointID: UUID,
        descriptor: CanonicalStoreDescriptor
    ) throws -> PendingCatalogInput {
        let snapshotQueue = try DatabaseQueue(path: snapshotURL.path)
        return try snapshotQueue.read { db in
            guard
                let metadata = try Row.fetchOne(
                    db,
                    sql: "SELECT schema_version FROM library_metadata WHERE id = 1"
                )
            else {
                throw DatabaseError(message: "Missing canonical library metadata")
            }
            let schemaVersion: Int = metadata["schema_version"]
            let recordCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM moment_record") ?? 0
            let tagCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tag_record") ?? 0
            let assetRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, content_hash, byte_count
                    FROM asset_record
                    ORDER BY id ASC
                    """
            )
            let assetStore = FileAssetStore(rootDirectory: descriptor.assetDirectoryURL)
            let manifest = try assetRows.map { row in
                let assetID = try row.canonicalUUID("id")
                let contentHash: String = row["content_hash"]
                let byteCount: Int64 = row["byte_count"]
                let storedAsset = try validateStoredAsset(
                    assetID: assetID,
                    contentHash: contentHash,
                    expectedByteCount: byteCount,
                    assetStore: assetStore
                )
                return try CanonicalPendingRestoreAsset(
                    assetID: assetID,
                    contentHash: contentHash,
                    byteCount: byteCount,
                    relativePath: relativePath(
                        for: storedAsset.fileURL,
                        rootDirectory: descriptor.rootDirectory
                    )
                )
            }
            return PendingCatalogInput(
                schemaVersion: schemaVersion,
                counts: CanonicalRecoveryPointCounts(
                    recordCount: recordCount,
                    tagCount: tagCount,
                    assetCount: manifest.count
                ),
                assetManifest: manifest
            )
        }
    }

    static func validateStoredAsset(
        assetID: UUID,
        contentHash: String,
        expectedByteCount: Int64,
        assetStore: FileAssetStore
    ) throws -> StoredFileAsset {
        do {
            let storedAsset = try assetStore.validateStoredAsset(forContentHash: contentHash)
            let actualByteCount = Int64(storedAsset.byteCount)
            guard actualByteCount == expectedByteCount else {
                throw CanonicalRestoreExecutorError.assetByteCountMismatch(
                    assetID: assetID,
                    expected: expectedByteCount,
                    actual: actualByteCount
                )
            }
            return storedAsset
        } catch FileAssetStoreError.missingAsset(let contentHash) {
            throw CanonicalRestoreExecutorError.missingAssetBlob(contentHash)
        } catch FileAssetStoreError.contentHashMismatch {
            throw CanonicalRestoreExecutorError.corruptAssetBlob(contentHash)
        }
    }

    static func clearPendingRestore(
        descriptor: CanonicalStoreDescriptor
    ) throws {
        let assetPinStore: CanonicalAssetPinStore?
        if FileManager.default.fileExists(atPath: descriptor.databaseURL.path) {
            assetPinStore = try CanonicalAssetPinStore(
                store: CanonicalStore(path: descriptor.databaseURL.path)
            )
        } else {
            assetPinStore = nil
        }
        try clearPendingRestore(descriptor: descriptor, assetPinStore: assetPinStore)
    }

    static func clearPendingRestore(
        descriptor: CanonicalStoreDescriptor,
        assetPinStore: CanonicalAssetPinStore?
    ) throws {
        let pendingDirectory = descriptor.pendingRestoreDirectory
        guard FileManager.default.fileExists(atPath: pendingDirectory.path) else {
            return
        }
        if let assetPinStore {
            do {
                if let context = try readContextIfPresent(in: pendingDirectory) {
                    try assetPinStore.releasePins(
                        ownerKind: .restoreStaging,
                        ownerID: context.restoreJobID.uuidString
                    )
                } else {
                    try assetPinStore.releasePins(ownerKind: .restoreStaging)
                }
            } catch {
                try assetPinStore.releasePins(ownerKind: .restoreStaging)
            }
        }
        try FileManager.default.removeItem(at: pendingDirectory)
    }

    static func payloadDirectory(in pendingDirectory: URL) -> URL {
        pendingDirectory.appendingPathComponent(payloadDirectoryName, isDirectory: true)
    }

    static func payloadDatabaseURL(
        in pendingDirectory: URL,
        descriptor: CanonicalStoreDescriptor
    ) -> URL {
        payloadDirectory(in: pendingDirectory).appendingPathComponent(
            descriptor.databaseURL.lastPathComponent
        )
    }

    static func writeContext(
        _ context: CanonicalPendingRestoreContext,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(context).write(to: url, options: [.atomic])
    }

    static func readContext(in pendingDirectory: URL) throws -> CanonicalPendingRestoreContext {
        guard let context = try readContextIfPresent(in: pendingDirectory) else {
            throw CanonicalRestoreExecutorError.missingPendingContext
        }
        return context
    }

    static func readContextIfPresent(
        in pendingDirectory: URL
    ) throws -> CanonicalPendingRestoreContext? {
        let url = pendingDirectory.appendingPathComponent(contextFileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try JSONDecoder().decode(
            CanonicalPendingRestoreContext.self,
            from: Data(contentsOf: url)
        )
    }

    static func absoluteURL(forRelativePath path: String, rootDirectory: URL) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/") else {
            throw CanonicalRestoreExecutorError.invalidRelativePath(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw CanonicalRestoreExecutorError.invalidRelativePath(path)
        }
        let url = rootDirectory.appendingPathComponent(path)
        _ = try relativePath(for: url, rootDirectory: rootDirectory)
        return url
    }

    static func relativePath(for url: URL, rootDirectory: URL) throws -> String {
        let rootPath = rootDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else {
            throw CanonicalRestoreExecutorError.fileOutsideRoot(path)
        }
        return String(path.dropFirst(rootPath.count + 1))
    }

    static func fileSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }
}
