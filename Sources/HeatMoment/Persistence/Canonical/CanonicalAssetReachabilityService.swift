import Foundation
import GRDB

struct CanonicalAssetReachabilityService: Sendable {
    let store: CanonicalStore
    let assetStore: FileAssetStore
    let operationGate: CanonicalAssetOperationGate

    init(
        store: CanonicalStore,
        assetStore: FileAssetStore,
        operationGate: CanonicalAssetOperationGate? = nil
    ) {
        self.store = store
        self.assetStore = assetStore
        self.operationGate =
            operationGate
            ?? CanonicalAssetOperationGate.shared(forAssetRootDirectory: assetStore.rootDirectory)
    }

    func audit(now: Date = .now) throws -> CanonicalAssetReachabilityReport {
        let allDatabaseContentHashes = try databaseContentHashes()
        let validDatabaseContentHashes = allDatabaseContentHashes.filter {
            FileAssetStore.isValidContentHash($0)
        }
        let invalidDatabaseContentHashes = allDatabaseContentHashes.filter {
            !FileAssetStore.isValidContentHash($0)
        }
        let databaseHashSet = Set(validDatabaseContentHashes)

        let listing = try assetStore.listStoredAssets()
        let storedHashSet = Set(listing.contentHashes)
        let corruptedStoredContentHashes = try corruptedStoredContentHashes(
            storedContentHashes: listing.contentHashes
        )
        let assetPinAudit = try CanonicalAssetPinAuditService(store: store).audit(now: now)
        let activePinnedHashSet = Set(assetPinAudit.activePinnedContentHashes)

        let missingDatabaseContentHashes =
            databaseHashSet
            .subtracting(storedHashSet)
            .sorted()
        let missingPinnedContentHashes =
            activePinnedHashSet
            .subtracting(storedHashSet)
            .sorted()
        let orphanStoredContentHashes =
            storedHashSet
            .subtracting(databaseHashSet)
            .subtracting(activePinnedHashSet)
            .subtracting(Set(corruptedStoredContentHashes))
            .sorted()

        return try CanonicalAssetReachabilityReport(
            databaseReferences: databaseReferences(for: validDatabaseContentHashes),
            unlinkedAssetRecords: unlinkedAssetRecords(validContentHashes: databaseHashSet),
            activePinnedContentHashes: assetPinAudit.activePinnedContentHashes,
            expiredAssetPinIDs: assetPinAudit.expiredAssetPinIDs,
            storedContentHashes: listing.contentHashes,
            invalidDatabaseContentHashes: invalidDatabaseContentHashes.sorted(),
            invalidAssetPinContentHashes: assetPinAudit.invalidContentHashes,
            invalidAssetPinLeaseIDs: assetPinAudit.invalidLeaseIDs,
            invalidPinCountAssetRecordIDs: try invalidPinCountAssetRecordIDs(),
            invalidStoredAssetPaths: listing.invalidRelativePaths,
            missingDatabaseContentHashes: missingDatabaseContentHashes,
            missingPinnedContentHashes: missingPinnedContentHashes,
            corruptedStoredContentHashes: corruptedStoredContentHashes,
            orphanStoredContentHashes: orphanStoredContentHashes
        )
    }

    func planGarbageCollection(now: Date = .now) throws -> CanonicalAssetGarbageCollectionPlan {
        let report = try audit(now: now)
        let finalizableAssetRecordIDs = report.unpinnedUnlinkedAssetRecords.map(\.assetID)
        let futureRemovableBlobHashes = futureRemovableBlobHashes(report: report)

        return CanonicalAssetGarbageCollectionPlan(
            report: report,
            finalizableAssetRecordIDs: finalizableAssetRecordIDs,
            currentOrphanBlobContentHashes: report.orphanStoredContentHashes,
            futureRemovableBlobHashes: futureRemovableBlobHashes
        )
    }

    @discardableResult
    func finalizeUnlinkedAssetRecords() throws -> CanonicalAssetRecordFinalizationResult {
        try operationGate.performSync {
            let plan = try planGarbageCollection()
            guard !plan.isBlocked else {
                throw CanonicalAssetReachabilityError.finalizationBlocked(plan)
            }

            let deletedAssetRecordIDs = try deleteUnlinkedUnpinnedAssetRecords(
                ids: plan.finalizableAssetRecordIDs
            )
            return CanonicalAssetRecordFinalizationResult(
                deletedAssetRecordIDs: deletedAssetRecordIDs,
                planBeforeFinalization: plan
            )
        }
    }

    @discardableResult
    func cleanupOrphanBlobs(now: Date = .now) throws -> CanonicalAssetCleanupResult {
        try operationGate.performSync {
            try cleanupOrphanBlobsWithoutGate(now: now)
        }
    }

    private func cleanupOrphanBlobsWithoutGate(now: Date) throws -> CanonicalAssetCleanupResult {
        let report = try audit(now: now)
        guard !report.hasBlockingIssue else {
            throw CanonicalAssetReachabilityError.cleanupBlocked(report)
        }

        for contentHash in report.orphanStoredContentHashes {
            try assetStore.removeBlob(forContentHash: contentHash)
        }

        return CanonicalAssetCleanupResult(
            removedContentHashes: report.orphanStoredContentHashes,
            reportBeforeCleanup: report
        )
    }
}

private extension CanonicalAssetReachabilityService {
    func futureRemovableBlobHashes(report: CanonicalAssetReachabilityReport) -> [String] {
        let storedContentHashes = Set(report.storedContentHashes)
        let activePinnedContentHashes = Set(report.activePinnedContentHashes)
        let finalizableRecordsByHash = Dictionary(
            grouping: report.unpinnedUnlinkedAssetRecords,
            by: \.contentHash
        )

        return report.databaseReferences.compactMap { reference in
            let finalizableRecordCount = finalizableRecordsByHash[reference.contentHash]?.count ?? 0
            guard reference.linkedAssetCount == 0 else { return nil }
            guard reference.totalPinCount == 0 else { return nil }
            guard reference.assetRecordCount == finalizableRecordCount else { return nil }
            guard storedContentHashes.contains(reference.contentHash) else { return nil }
            guard !activePinnedContentHashes.contains(reference.contentHash) else { return nil }
            return reference.contentHash
        }
    }

    func deleteUnlinkedUnpinnedAssetRecords(ids: [UUID]) throws -> [UUID] {
        guard !ids.isEmpty else { return [] }

        return try store.write { db in
            var eligibleIDs: [UUID] = []
            for id in ids {
                if let row = try eligibleUnlinkedUnpinnedAssetRecord(id: id, db: db) {
                    eligibleIDs.append(try row.canonicalUUID("id"))
                }
            }
            guard eligibleIDs == ids else {
                throw CanonicalAssetReachabilityError.finalizationRace(
                    expectedAssetRecordIDs: ids,
                    deletedAssetRecordIDs: []
                )
            }

            for id in ids {
                try db.execute(
                    sql: "DELETE FROM asset_record WHERE id = ?",
                    arguments: [id.uuidString]
                )
            }
            return ids
        }
    }

    func eligibleUnlinkedUnpinnedAssetRecord(id: UUID, db: Database) throws -> Row? {
        try Row.fetchOne(
            db,
            sql: """
                SELECT id
                FROM asset_record
                WHERE id = ?
                    AND pin_count = 0
                    AND NOT EXISTS (
                        SELECT 1
                        FROM moment_asset_link
                        WHERE moment_asset_link.asset_id = asset_record.id
                    )
                """,
            arguments: [id.uuidString]
        )
    }

    func databaseContentHashes() throws -> [String] {
        try store.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT content_hash
                    FROM asset_record
                    ORDER BY content_hash ASC
                    """
            )
        }
    }

    func invalidPinCountAssetRecordIDs() throws -> [UUID] {
        try store.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id
                    FROM asset_record
                    WHERE pin_count < 0
                    ORDER BY id ASC
                    """
            )
            return try rows.map { row in
                try row.canonicalUUID("id")
            }
        }
    }

    func databaseReferences(
        for validContentHashes: [String]
    ) throws -> [CanonicalAssetDatabaseReference] {
        guard !validContentHashes.isEmpty else { return [] }
        let validContentHashSet = Set(validContentHashes)
        let rows = try store.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT asset_record.id, asset_record.content_hash, asset_record.pin_count,
                        COUNT(moment_asset_link.asset_id) AS linked_asset_count
                    FROM asset_record
                    LEFT JOIN moment_asset_link ON moment_asset_link.asset_id = asset_record.id
                    GROUP BY asset_record.id
                    ORDER BY asset_record.content_hash ASC, asset_record.id ASC
                    """
            )
        }

        var grouped: [String: AssetRefAccumulator] = [:]
        for row in rows {
            let contentHash: String = row["content_hash"]
            guard validContentHashSet.contains(contentHash) else { continue }
            var accumulator = grouped[contentHash] ?? AssetRefAccumulator()
            accumulator.assetRecordCount += 1
            accumulator.linkedAssetCount += row["linked_asset_count"] as Int
            accumulator.totalPinCount += row["pin_count"] as Int
            grouped[contentHash] = accumulator
        }

        return grouped.keys.sorted().map { contentHash in
            let accumulator = grouped[contentHash] ?? AssetRefAccumulator()
            return CanonicalAssetDatabaseReference(
                contentHash: contentHash,
                assetRecordCount: accumulator.assetRecordCount,
                linkedAssetCount: accumulator.linkedAssetCount,
                totalPinCount: accumulator.totalPinCount
            )
        }
    }

    func unlinkedAssetRecords(
        validContentHashes: Set<String>
    ) throws -> [CanonicalUnlinkedAssetRecord] {
        try store.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT asset_record.id, asset_record.content_hash, asset_record.pin_count
                    FROM asset_record
                    LEFT JOIN moment_asset_link ON moment_asset_link.asset_id = asset_record.id
                    WHERE moment_asset_link.asset_id IS NULL
                    ORDER BY asset_record.content_hash ASC, asset_record.id ASC
                    """
            )
            return try rows.compactMap { row in
                let contentHash: String = row["content_hash"]
                guard validContentHashes.contains(contentHash) else { return nil }
                return try CanonicalUnlinkedAssetRecord(
                    assetID: row.canonicalUUID("id"),
                    contentHash: contentHash,
                    pinCount: row["pin_count"]
                )
            }
        }
    }

    func corruptedStoredContentHashes(
        storedContentHashes: [String]
    ) throws -> [String] {
        var corrupted: [String] = []
        for contentHash in storedContentHashes {
            do {
                _ = try assetStore.validateStoredAsset(forContentHash: contentHash)
            } catch FileAssetStoreError.contentHashMismatch {
                corrupted.append(contentHash)
            } catch {
                throw error
            }
        }
        return corrupted.sorted()
    }
}

private struct AssetRefAccumulator {
    var assetRecordCount = 0
    var linkedAssetCount = 0
    var totalPinCount = 0
}
