import Foundation
import GRDB

enum CanonicalRecoveryPointStoreError: Error, Equatable {
    case emptyAppVersion
    case invalidSnapshotRelativePath(String)
    case invalidSnapshotByteCount(Int64)
    case invalidSnapshotHash(String)
    case invalidCount(name: String, value: Int)
    case assetManifestCountMismatch(expected: Int, actual: Int)
    case mismatchedAssetRecoveryPointID(assetID: UUID, recoveryPointID: UUID)
    case invalidAssetContentHash(String)
    case invalidAssetByteCount(Int64)
    case invalidAssetRelativePath(String)
    case duplicateAssetID(UUID)
}

struct CanonicalRecoveryPointStore: Sendable {
    static let retainedRecoveryPointLimit = 3

    let store: CanonicalStore

    func createRecoveryPoint(
        _ request: CanonicalRecoveryPointCreationRequest,
        enforcesRetention: Bool = true
    ) throws -> CanonicalRecoveryPointCreationResult {
        let record = CanonicalRecoveryPointRecord(
            id: request.id,
            createdAt: request.createdAt,
            reason: request.reason,
            status: .available,
            schemaVersion: request.schemaVersion,
            appVersion: request.appVersion,
            sourceLibraryID: request.sourceLibraryID,
            sqliteSnapshot: request.sqliteSnapshot,
            counts: request.counts
        )
        try validate(record: record, assetManifest: request.assetManifest)

        return try store.write { db in
            try insert(record: record, db: db)
            try insert(
                assetManifest: request.assetManifest,
                recoveryPointID: request.id,
                createdAt: request.createdAt,
                db: db
            )
            let evictedIDs =
                enforcesRetention
                ? try evictOverflowRecoveryPoints(db: db)
                : []
            return CanonicalRecoveryPointCreationResult(
                recoveryPoint: record,
                evictedRecoveryPointIDs: evictedIDs
            )
        }
    }

    func evictOverflowRecoveryPoints() throws -> [UUID] {
        try store.write { db in
            try evictOverflowRecoveryPoints(db: db)
        }
    }

    @discardableResult
    func deleteRecoveryPoint(id: UUID) throws -> Bool {
        try store.write { db in
            let exists =
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM recovery_point_record WHERE id = ?",
                    arguments: [id.uuidString]
                ) ?? 0
            guard exists > 0 else { return false }

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
            return true
        }
    }

    func listRecoveryPoints() throws -> [CanonicalRecoveryPointRecord] {
        try store.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM recovery_point_record
                    ORDER BY created_at DESC, id DESC
                    """
            )
            return try rows.map(makeRecoveryPointRecord(row:))
        }
    }

    func assetManifest(for recoveryPointID: UUID) throws -> [CanonicalRecoveryPointAssetRecord] {
        try store.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM recovery_point_asset_record
                    WHERE recovery_point_id = ?
                    ORDER BY asset_id ASC
                    """,
                arguments: [recoveryPointID.uuidString]
            )
            return try rows.map(makeAssetRecord(row:))
        }
    }

    func recoveryPoint(id: UUID) throws -> CanonicalRecoveryPointRecord? {
        try store.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM recovery_point_record WHERE id = ?",
                arguments: [id.uuidString]
            )
            return try row.map(makeRecoveryPointRecord(row:))
        }
    }

    @discardableResult
    func updateStatus(
        _ status: CanonicalRecoveryPointStatus,
        for id: UUID
    ) throws -> CanonicalRecoveryPointRecord? {
        try store.write { db in
            try db.execute(
                sql: "UPDATE recovery_point_record SET status = ? WHERE id = ?",
                arguments: [status.rawValue, id.uuidString]
            )
            let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM recovery_point_record WHERE id = ?",
                arguments: [id.uuidString]
            )
            return try row.map(makeRecoveryPointRecord(row:))
        }
    }
}

private extension CanonicalRecoveryPointStore {
    func validate(
        record: CanonicalRecoveryPointRecord,
        assetManifest: [CanonicalRecoveryPointAssetRecord]
    ) throws {
        guard !record.appVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CanonicalRecoveryPointStoreError.emptyAppVersion
        }
        guard isValidRelativePath(record.sqliteSnapshot.relativePath) else {
            throw CanonicalRecoveryPointStoreError.invalidSnapshotRelativePath(
                record.sqliteSnapshot.relativePath
            )
        }
        guard record.sqliteSnapshot.byteCount >= 0 else {
            throw CanonicalRecoveryPointStoreError.invalidSnapshotByteCount(
                record.sqliteSnapshot.byteCount
            )
        }
        guard FileAssetStore.isValidContentHash(record.sqliteSnapshot.sha256) else {
            throw CanonicalRecoveryPointStoreError.invalidSnapshotHash(record.sqliteSnapshot.sha256)
        }
        try validateCount(record.counts.recordCount, name: "recordCount")
        try validateCount(record.counts.tagCount, name: "tagCount")
        try validateCount(record.counts.assetCount, name: "assetCount")
        guard record.counts.assetCount == assetManifest.count else {
            throw CanonicalRecoveryPointStoreError.assetManifestCountMismatch(
                expected: record.counts.assetCount,
                actual: assetManifest.count
            )
        }

        var assetIDs = Set<UUID>()
        for asset in assetManifest {
            guard asset.recoveryPointID == record.id else {
                throw CanonicalRecoveryPointStoreError.mismatchedAssetRecoveryPointID(
                    assetID: asset.assetID,
                    recoveryPointID: asset.recoveryPointID
                )
            }
            guard assetIDs.insert(asset.assetID).inserted else {
                throw CanonicalRecoveryPointStoreError.duplicateAssetID(asset.assetID)
            }
            guard FileAssetStore.isValidContentHash(asset.contentHash) else {
                throw CanonicalRecoveryPointStoreError.invalidAssetContentHash(asset.contentHash)
            }
            guard asset.byteCount >= 0 else {
                throw CanonicalRecoveryPointStoreError.invalidAssetByteCount(asset.byteCount)
            }
            guard isValidRelativePath(asset.relativePath) else {
                throw CanonicalRecoveryPointStoreError.invalidAssetRelativePath(asset.relativePath)
            }
        }
    }

    func validateCount(_ value: Int, name: String) throws {
        guard value >= 0 else {
            throw CanonicalRecoveryPointStoreError.invalidCount(name: name, value: value)
        }
    }

    func isValidRelativePath(_ relativePath: String) -> Bool {
        guard !relativePath.isEmpty else { return false }
        guard !relativePath.hasPrefix("/") else { return false }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
    }

    func insert(record: CanonicalRecoveryPointRecord, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO recovery_point_record (
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
                record.counts.assetCount
            ]
        )
    }

    func insert(
        assetManifest: [CanonicalRecoveryPointAssetRecord],
        recoveryPointID: UUID,
        createdAt: Date,
        db: Database
    ) throws {
        for asset in assetManifest {
            try db.execute(
                sql: """
                    INSERT INTO recovery_point_asset_record (
                        recovery_point_id, asset_id, content_hash, byte_count, relative_path
                    ) VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    recoveryPointID.uuidString,
                    asset.assetID.uuidString,
                    asset.contentHash,
                    asset.byteCount,
                    asset.relativePath
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
                    recoveryPointID.uuidString,
                    createdAt.timeIntervalSince1970
                ]
            )
        }
    }

    func evictOverflowRecoveryPoints(db: Database) throws -> [UUID] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT id
                FROM recovery_point_record
                ORDER BY created_at DESC, id DESC
                """
        )
        let retainedIDs = try rows.prefix(Self.retainedRecoveryPointLimit).map { row in
            try row.canonicalUUID("id")
        }
        let evictedIDs = try rows.dropFirst(Self.retainedRecoveryPointLimit).map { row in
            try row.canonicalUUID("id")
        }
        guard !evictedIDs.isEmpty else { return [] }

        let retainedIDSet = Set(retainedIDs)
        for id in evictedIDs where !retainedIDSet.contains(id) {
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
        return evictedIDs
    }

    func makeRecoveryPointRecord(row: Row) throws -> CanonicalRecoveryPointRecord {
        let reasonRawValue: String = row["reason"]
        let statusRawValue: String = row["status"]
        guard let reason = CanonicalRecoveryPointReason(rawValue: reasonRawValue) else {
            throw DatabaseError(message: "Invalid recovery point reason: \(reasonRawValue)")
        }
        guard let status = CanonicalRecoveryPointStatus(rawValue: statusRawValue) else {
            throw DatabaseError(message: "Invalid recovery point status: \(statusRawValue)")
        }
        return try CanonicalRecoveryPointRecord(
            id: row.canonicalUUID("id"),
            createdAt: row.canonicalDate("created_at"),
            reason: reason,
            status: status,
            schemaVersion: row["schema_version"],
            appVersion: row["app_version"],
            sourceLibraryID: row.canonicalUUID("source_library_id"),
            sqliteSnapshot: CanonicalRecoveryPointSnapshot(
                relativePath: row["sqlite_snapshot_relative_path"],
                byteCount: row["sqlite_snapshot_byte_count"],
                sha256: row["sqlite_snapshot_sha256"]
            ),
            counts: CanonicalRecoveryPointCounts(
                recordCount: row["record_count"],
                tagCount: row["tag_count"],
                assetCount: row["asset_count"]
            )
        )
    }

    func makeAssetRecord(row: Row) throws -> CanonicalRecoveryPointAssetRecord {
        try CanonicalRecoveryPointAssetRecord(
            recoveryPointID: row.canonicalUUID("recovery_point_id"),
            assetID: row.canonicalUUID("asset_id"),
            contentHash: row["content_hash"],
            byteCount: row["byte_count"],
            relativePath: row["relative_path"]
        )
    }
}
