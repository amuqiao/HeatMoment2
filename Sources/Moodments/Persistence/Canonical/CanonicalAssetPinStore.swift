import Foundation
import GRDB

enum CanonicalAssetPinStoreError: Error, Equatable {
    case invalidContentHash(String)
    case invalidOwnerID
    case invalidExpiration(createdAt: Date, expiresAt: Date)
}

struct CanonicalAssetPinStore: Sendable {
    let store: CanonicalStore

    @discardableResult
    func pinContentHash(
        _ contentHash: String,
        ownerKind: CanonicalAssetPinOwnerKind,
        ownerID: String,
        createdAt: Date = .now,
        expiresAt: Date? = nil
    ) throws -> CanonicalAssetPinRecord {
        try validate(
            contentHash: contentHash,
            ownerID: ownerID,
            createdAt: createdAt,
            expiresAt: expiresAt
        )
        let id = UUID()
        return try store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO asset_pin_record (
                        id, content_hash, owner_kind, owner_id, created_at, expires_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(content_hash, owner_kind, owner_id) DO UPDATE SET
                        created_at = excluded.created_at,
                        expires_at = excluded.expires_at
                    """,
                arguments: [
                    id.uuidString,
                    contentHash,
                    ownerKind.rawValue,
                    ownerID,
                    createdAt.timeIntervalSince1970,
                    expiresAt?.timeIntervalSince1970,
                ]
            )
            return try fetchPin(
                contentHash: contentHash,
                ownerKind: ownerKind,
                ownerID: ownerID,
                db: db
            )
        }
    }

    @discardableResult
    func releaseContentHashPin(
        contentHash: String,
        ownerKind: CanonicalAssetPinOwnerKind,
        ownerID: String
    ) throws -> Bool {
        try validate(contentHash: contentHash, ownerID: ownerID)
        return try store.write { db in
            try db.execute(
                sql: """
                    DELETE FROM asset_pin_record
                    WHERE content_hash = ? AND owner_kind = ? AND owner_id = ?
                    """,
                arguments: [contentHash, ownerKind.rawValue, ownerID]
            )
            return db.changesCount > 0
        }
    }
}

private extension CanonicalAssetPinStore {
    func validate(
        contentHash: String,
        ownerID: String,
        createdAt: Date = .now,
        expiresAt: Date? = nil
    ) throws {
        guard FileAssetStore.isValidContentHash(contentHash) else {
            throw CanonicalAssetPinStoreError.invalidContentHash(contentHash)
        }
        guard !ownerID.isEmpty else {
            throw CanonicalAssetPinStoreError.invalidOwnerID
        }
        if let expiresAt, expiresAt <= createdAt {
            throw CanonicalAssetPinStoreError.invalidExpiration(
                createdAt: createdAt,
                expiresAt: expiresAt
            )
        }
    }

    func fetchPin(
        contentHash: String,
        ownerKind: CanonicalAssetPinOwnerKind,
        ownerID: String,
        db: Database
    ) throws -> CanonicalAssetPinRecord {
        guard
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT *
                    FROM asset_pin_record
                    WHERE content_hash = ? AND owner_kind = ? AND owner_id = ?
                    """,
                arguments: [contentHash, ownerKind.rawValue, ownerID]
            )
        else {
            throw DatabaseError(message: "Missing asset content pin")
        }
        return try CanonicalAssetPinRecord(
            id: row.canonicalUUID("id"),
            contentHash: row["content_hash"],
            ownerKind: ownerKind,
            ownerID: row["owner_id"],
            createdAt: row.canonicalDate("created_at"),
            expiresAt: row.canonicalOptionalDate("expires_at")
        )
    }
}
