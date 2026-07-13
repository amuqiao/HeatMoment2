import Foundation
import GRDB

struct CanonicalAssetPinAudit: Sendable, Equatable {
    let activePinnedContentHashes: [String]
    let expiredAssetPinIDs: [UUID]
    let invalidContentHashes: [String]
    let invalidLeaseIDs: [UUID]
}

struct CanonicalAssetPinAuditService: Sendable {
    let store: CanonicalStore

    func audit(now: Date) throws -> CanonicalAssetPinAudit {
        try store.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, content_hash, created_at, expires_at
                    FROM asset_pin_record
                    ORDER BY content_hash ASC, id ASC
                    """
            )
            var activePinnedContentHashes: Set<String> = []
            var expiredAssetPinIDs: [UUID] = []
            var invalidContentHashes: Set<String> = []
            var invalidLeaseIDs: [UUID] = []

            for row in rows {
                let id = try row.canonicalUUID("id")
                let contentHash: String = row["content_hash"]
                let createdAt: Double = row["created_at"]
                let expiresAt: Double? = row["expires_at"]

                guard FileAssetStore.isValidContentHash(contentHash) else {
                    invalidContentHashes.insert(contentHash)
                    continue
                }
                if let expiresAt, expiresAt <= createdAt {
                    invalidLeaseIDs.append(id)
                    continue
                }
                if let expiresAt, expiresAt <= now.timeIntervalSince1970 {
                    expiredAssetPinIDs.append(id)
                } else {
                    activePinnedContentHashes.insert(contentHash)
                }
            }

            return CanonicalAssetPinAudit(
                activePinnedContentHashes: activePinnedContentHashes.sorted(),
                expiredAssetPinIDs: expiredAssetPinIDs,
                invalidContentHashes: invalidContentHashes.sorted(),
                invalidLeaseIDs: invalidLeaseIDs
            )
        }
    }
}
