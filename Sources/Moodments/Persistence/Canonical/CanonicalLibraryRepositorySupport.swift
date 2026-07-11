import Foundation
import GRDB
import UIKit

extension CanonicalLibraryRepository {
    struct PreparedAsset {
        let id: UUID
        let contentHash: String
        let mimeType: String
        let byteCount: Int
        let width: Int?
        let height: Int?
        let storedFileAsset: StoredFileAsset
    }

    struct AssetRecord {
        let contentHash: String
    }

    static func yearInterval(year: Int) -> DateInterval {
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        let calendar = Calendar.current
        guard let start = calendar.date(from: components) else {
            preconditionFailure("年份起始日期合成失败：\(year)")
        }
        guard let end = calendar.date(byAdding: .year, value: 1, to: start) else {
            preconditionFailure("年份结束日期合成失败：\(year)")
        }
        return DateInterval(start: start, end: end)
    }

    static func mimeType(data: Data) -> String {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "image/png"
        }
        return "application/octet-stream"
    }

    static func imageDimensions(data: Data) -> (width: Int?, height: Int?) {
        guard let image = UIImage(data: data) else {
            return (nil, nil)
        }
        return (Int(image.size.width), Int(image.size.height))
    }

    func insertMutation(
        entityType: String,
        entityID: UUID,
        operation: String,
        recordRevision: Int,
        now: Date,
        db: Database
    ) throws {
        let metadata = try metadata(db: db)
        try db.execute(
            sql: """
                INSERT INTO mutation_log (
                    id, entity_type, entity_id, operation, occurred_at, device_id, record_revision
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                UUID().uuidString,
                entityType,
                entityID.uuidString,
                operation,
                now.timeIntervalSince1970,
                metadata.deviceID.uuidString,
                recordRevision,
            ]
        )
    }

    func insertTombstone(
        entityType: String,
        entityID: UUID,
        operation: String,
        recordRevision: Int,
        now: Date,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO tombstone_record (
                    id, entity_type, entity_id, operation, created_at, record_revision
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                UUID().uuidString,
                entityType,
                entityID.uuidString,
                operation,
                now.timeIntervalSince1970,
                recordRevision,
            ]
        )
    }

    func metadata(db: Database) throws -> CanonicalLibraryMetadata {
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
            updatedAt: row.canonicalDate("updated_at"),
            swiftDataImportedAt: row.canonicalOptionalDate("swift_data_imported_at"),
            swiftDataImportSourceFingerprint: row["swift_data_import_source_fingerprint"]
        )
    }
}
