import Foundation
import GRDB

enum RecoveryPointSnapshotServiceError: Error, Equatable {
    case recoveryPointNotFound(UUID)
    case recoveryPointDirectoryAlreadyExists(String)
    case invalidRelativePath(String)
    case fileOutsideRoot(String)
    case missingSnapshotFile(String)
    case snapshotByteCountMismatch(expected: Int64, actual: Int64)
    case snapshotHashMismatch(expected: String, actual: String)
    case snapshotSchemaVersionMismatch(expected: Int, actual: Int)
    case catalogCountsMismatch(
        expected: CanonicalRecoveryPointCounts,
        actual: CanonicalRecoveryPointCounts
    )
    case assetManifestCountMismatch(expected: Int, actual: Int)
    case assetManifestMismatch
    case missingAssetBlob(String)
    case corruptAssetBlob(String)
    case assetByteCountMismatch(assetID: UUID, expected: Int64, actual: Int64)
    case statusUpdateFailed(validationError: String, statusError: String)
}

struct RecoveryPointSnapshotRequest: Sendable, Equatable {
    let id: UUID
    let reason: CanonicalRecoveryPointReason
    let createdAt: Date
    let appVersion: String
}

struct RecoveryPointDirectoryReconciliationResult: Sendable, Equatable {
    let removedDirectoryNames: [String]
}

struct CanonicalRecoveryPointSnapshotService: Sendable {
    static let snapshotFileName = "Library.sqlite"

    let store: CanonicalStore
    let recoveryPointStore: CanonicalRecoveryPointStore
    let assetStore: FileAssetStore
    let operationGate: CanonicalAssetOperationGate
    let rootDirectory: URL
    let recoveryPointDirectoryURL: URL

    init(
        store: CanonicalStore,
        recoveryPointStore: CanonicalRecoveryPointStore,
        assetStore: FileAssetStore,
        operationGate: CanonicalAssetOperationGate? = nil,
        rootDirectory: URL,
        recoveryPointDirectoryURL: URL
    ) {
        self.store = store
        self.recoveryPointStore = recoveryPointStore
        self.assetStore = assetStore
        self.operationGate =
            operationGate
            ?? CanonicalAssetOperationGate.shared(forAssetRootDirectory: assetStore.rootDirectory)
        self.rootDirectory = rootDirectory
        self.recoveryPointDirectoryURL = recoveryPointDirectoryURL
    }

    @discardableResult
    func createRecoveryPoint(
        _ request: RecoveryPointSnapshotRequest,
        enforcesRetention: Bool = true
    ) throws -> CanonicalRecoveryPointCreationResult {
        try operationGate.performSync {
            try createRecoveryPointWithoutGate(
                request,
                enforcesRetention: enforcesRetention
            )
        }
    }

    @discardableResult
    func validateRecoveryPoint(id: UUID) throws -> CanonicalRecoveryPointRecord {
        try operationGate.performSync {
            try validateRecoveryPointWithoutGate(id: id)
        }
    }

    func reconcileRecoveryPointDirectories() throws -> RecoveryPointDirectoryReconciliationResult {
        try operationGate.performSync {
            try reconcileRecoveryPointDirectoriesWithoutGate()
        }
    }

    @discardableResult
    func enforceRecoveryPointRetention() throws -> [UUID] {
        try operationGate.performSync {
            let evictedIDs = try recoveryPointStore.evictOverflowRecoveryPoints()
            try removeEvictedRecoveryPointDirectories(evictedIDs)
            return evictedIDs
        }
    }

    func deleteRecoveryPoint(id: UUID) throws {
        try operationGate.performSync {
            let deleted = try recoveryPointStore.deleteRecoveryPoint(id: id)
            guard deleted else { return }
            let directory = directory(for: id)
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
    }
}

private extension CanonicalRecoveryPointSnapshotService {
    struct CatalogInput {
        let sourceLibraryID: UUID
        let schemaVersion: Int
        let counts: CanonicalRecoveryPointCounts
        let assetManifest: [CanonicalRecoveryPointAssetRecord]
    }

    func createRecoveryPointWithoutGate(
        _ request: RecoveryPointSnapshotRequest,
        enforcesRetention: Bool
    ) throws -> CanonicalRecoveryPointCreationResult {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: recoveryPointDirectoryURL,
            withIntermediateDirectories: true
        )

        let pointDirectory = directory(for: request.id)
        guard !fileManager.fileExists(atPath: pointDirectory.path) else {
            throw
                RecoveryPointSnapshotServiceError
                .recoveryPointDirectoryAlreadyExists(pointDirectory.path)
        }

        let stagingDirectory = recoveryPointDirectoryURL.appendingPathComponent(
            "staging",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let temporaryURL = stagingDirectory.appendingPathComponent(
            "\(request.id.uuidString)-\(UUID().uuidString).sqlite"
        )
        defer {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        try store.backup(to: temporaryURL)
        let catalog = try makeCatalogInput(
            fromSnapshotAt: temporaryURL,
            recoveryPointID: request.id
        )
        let snapshotData = try Data(contentsOf: temporaryURL)
        let finalSnapshotURL = snapshotURL(for: request.id)
        let snapshot = try CanonicalRecoveryPointSnapshot(
            relativePath: relativePath(for: finalSnapshotURL),
            byteCount: Int64(snapshotData.count),
            sha256: FileAssetStore.sha256Hex(snapshotData)
        )

        try fileManager.createDirectory(at: pointDirectory, withIntermediateDirectories: true)
        do {
            try fileManager.moveItem(at: temporaryURL, to: finalSnapshotURL)
        } catch {
            try? fileManager.removeItem(at: pointDirectory)
            throw error
        }

        do {
            let creationResult = try recoveryPointStore.createRecoveryPoint(
                CanonicalRecoveryPointCreationRequest(
                    id: request.id,
                    reason: request.reason,
                    createdAt: request.createdAt,
                    schemaVersion: catalog.schemaVersion,
                    appVersion: request.appVersion,
                    sourceLibraryID: catalog.sourceLibraryID,
                    sqliteSnapshot: snapshot,
                    counts: catalog.counts,
                    assetManifest: catalog.assetManifest
                ),
                enforcesRetention: enforcesRetention
            )
            try removeEvictedRecoveryPointDirectories(creationResult.evictedRecoveryPointIDs)
            return creationResult
        } catch {
            try? fileManager.removeItem(at: pointDirectory)
            throw error
        }
    }

    func validateRecoveryPointWithoutGate(id: UUID) throws -> CanonicalRecoveryPointRecord {
        guard let record = try recoveryPointStore.recoveryPoint(id: id) else {
            throw RecoveryPointSnapshotServiceError.recoveryPointNotFound(id)
        }

        do {
            try validate(record)
        } catch {
            let validationError = error
            do {
                _ = try recoveryPointStore.updateStatus(.invalid, for: id)
            } catch {
                throw RecoveryPointSnapshotServiceError.statusUpdateFailed(
                    validationError: String(describing: validationError),
                    statusError: String(describing: error)
                )
            }
            throw validationError
        }
        return try recoveryPointStore.updateStatus(.available, for: id) ?? record
    }

    func makeCatalogInput(
        fromSnapshotAt snapshotURL: URL,
        recoveryPointID: UUID
    ) throws -> CatalogInput {
        let snapshotQueue = try DatabaseQueue(path: snapshotURL.path)
        return try snapshotQueue.read { db in
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
            let sourceLibraryID = try metadata.canonicalUUID("library_id")
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
            let manifest = try assetRows.map { row in
                let assetID = try row.canonicalUUID("id")
                let contentHash: String = row["content_hash"]
                let byteCount: Int64 = row["byte_count"]
                let storedAsset = try validateStoredAsset(
                    assetID: assetID,
                    contentHash: contentHash,
                    expectedByteCount: byteCount
                )
                return try CanonicalRecoveryPointAssetRecord(
                    recoveryPointID: recoveryPointID,
                    assetID: assetID,
                    contentHash: contentHash,
                    byteCount: byteCount,
                    relativePath: relativePath(for: storedAsset.fileURL)
                )
            }

            return CatalogInput(
                sourceLibraryID: sourceLibraryID,
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

    func validate(_ record: CanonicalRecoveryPointRecord) throws {
        let snapshotURL = try absoluteURL(forRelativePath: record.sqliteSnapshot.relativePath)
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            throw
                RecoveryPointSnapshotServiceError
                .missingSnapshotFile(snapshotURL.path)
        }

        let actualByteCount = try fileSize(snapshotURL)
        guard actualByteCount == record.sqliteSnapshot.byteCount else {
            throw RecoveryPointSnapshotServiceError.snapshotByteCountMismatch(
                expected: record.sqliteSnapshot.byteCount,
                actual: actualByteCount
            )
        }

        let snapshotData = try Data(contentsOf: snapshotURL)
        let actualHash = FileAssetStore.sha256Hex(snapshotData)
        guard actualHash == record.sqliteSnapshot.sha256 else {
            throw RecoveryPointSnapshotServiceError.snapshotHashMismatch(
                expected: record.sqliteSnapshot.sha256,
                actual: actualHash
            )
        }

        let snapshotQueue = try DatabaseQueue(path: snapshotURL.path)
        let actualSchemaVersion = try snapshotQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT schema_version FROM library_metadata WHERE id = 1"
            ) ?? 0
        }
        guard actualSchemaVersion == record.schemaVersion else {
            throw RecoveryPointSnapshotServiceError.snapshotSchemaVersionMismatch(
                expected: record.schemaVersion,
                actual: actualSchemaVersion
            )
        }

        let snapshotCatalog = try makeCatalogInput(
            fromSnapshotAt: snapshotURL,
            recoveryPointID: record.id
        )
        guard snapshotCatalog.counts == record.counts else {
            throw RecoveryPointSnapshotServiceError.catalogCountsMismatch(
                expected: record.counts,
                actual: snapshotCatalog.counts
            )
        }

        let catalogManifest = try recoveryPointStore.assetManifest(for: record.id)
        guard catalogManifest.count == record.counts.assetCount else {
            throw RecoveryPointSnapshotServiceError.assetManifestCountMismatch(
                expected: record.counts.assetCount,
                actual: catalogManifest.count
            )
        }
        guard catalogManifest == snapshotCatalog.assetManifest else {
            throw RecoveryPointSnapshotServiceError.assetManifestMismatch
        }
    }

    func validateStoredAsset(
        assetID: UUID,
        contentHash: String,
        expectedByteCount: Int64
    ) throws -> StoredFileAsset {
        do {
            let storedAsset = try assetStore.validateStoredAsset(forContentHash: contentHash)
            let actualByteCount = Int64(storedAsset.byteCount)
            guard actualByteCount == expectedByteCount else {
                throw RecoveryPointSnapshotServiceError.assetByteCountMismatch(
                    assetID: assetID,
                    expected: expectedByteCount,
                    actual: actualByteCount
                )
            }
            return storedAsset
        } catch FileAssetStoreError.missingAsset(let contentHash) {
            throw RecoveryPointSnapshotServiceError.missingAssetBlob(contentHash)
        } catch FileAssetStoreError.contentHashMismatch {
            throw RecoveryPointSnapshotServiceError.corruptAssetBlob(contentHash)
        }
    }

    func directory(for recoveryPointID: UUID) -> URL {
        recoveryPointDirectoryURL.appendingPathComponent(
            recoveryPointID.uuidString,
            isDirectory: true
        )
    }

    func snapshotURL(for recoveryPointID: UUID) -> URL {
        directory(for: recoveryPointID)
            .appendingPathComponent(Self.snapshotFileName)
    }

    func removeEvictedRecoveryPointDirectories(_ ids: [UUID]) throws {
        for id in ids {
            let directory = directory(for: id)
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
    }

    func reconcileRecoveryPointDirectoriesWithoutGate() throws
        -> RecoveryPointDirectoryReconciliationResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: recoveryPointDirectoryURL.path) else {
            return RecoveryPointDirectoryReconciliationResult(removedDirectoryNames: [])
        }

        let catalogIDs = Set(try recoveryPointStore.listRecoveryPoints().map(\.id))
        let children = try fileManager.contentsOfDirectory(
            at: recoveryPointDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var removedNames: [String] = []
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }

            let name = child.lastPathComponent
            if name == "staging" {
                try fileManager.removeItem(at: child)
                removedNames.append(name)
                continue
            }
            guard let recoveryPointID = UUID(uuidString: name),
                catalogIDs.contains(recoveryPointID)
            else {
                try fileManager.removeItem(at: child)
                removedNames.append(name)
                continue
            }
        }
        return RecoveryPointDirectoryReconciliationResult(removedDirectoryNames: removedNames)
    }

    func absoluteURL(forRelativePath path: String) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/") else {
            throw RecoveryPointSnapshotServiceError.invalidRelativePath(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw RecoveryPointSnapshotServiceError.invalidRelativePath(path)
        }
        let url = rootDirectory.appendingPathComponent(path)
        _ = try relativePath(for: url)
        return url
    }

    func relativePath(for url: URL) throws -> String {
        let rootPath = rootDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else {
            throw RecoveryPointSnapshotServiceError.fileOutsideRoot(path)
        }
        return String(path.dropFirst(rootPath.count + 1))
    }

    func fileSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }
}
