import Foundation
import GRDB

enum CanonicalAssetReachabilityError: Error, Equatable {
    case cleanupBlocked(CanonicalAssetReachabilityReport)
}

struct CanonicalAssetDatabaseReference: Sendable, Equatable {
    let contentHash: String
    let assetRecordCount: Int
    let linkedAssetCount: Int
    let totalPinCount: Int

    var isPinned: Bool {
        totalPinCount > 0
    }
}

struct CanonicalUnlinkedAssetRecord: Sendable, Equatable {
    let assetID: UUID
    let contentHash: String
    let pinCount: Int
}

struct CanonicalAssetReachabilityReport: Sendable, Equatable {
    let databaseReferences: [CanonicalAssetDatabaseReference]
    let unlinkedAssetRecords: [CanonicalUnlinkedAssetRecord]
    let storedContentHashes: [String]
    let invalidDatabaseContentHashes: [String]
    let invalidStoredAssetPaths: [String]
    let missingDatabaseContentHashes: [String]
    let corruptedStoredContentHashes: [String]
    let orphanStoredContentHashes: [String]

    var databaseContentHashes: [String] {
        databaseReferences.map(\.contentHash)
    }

    var linkedContentHashes: [String] {
        databaseReferences
            .filter { $0.linkedAssetCount > 0 }
            .map(\.contentHash)
    }

    var pinnedContentHashes: [String] {
        databaseReferences
            .filter(\.isPinned)
            .map(\.contentHash)
    }

    var unpinnedUnlinkedAssetRecords: [CanonicalUnlinkedAssetRecord] {
        unlinkedAssetRecords.filter { $0.pinCount == 0 }
    }

    var hasBlockingIssue: Bool {
        !invalidDatabaseContentHashes.isEmpty
            || !invalidStoredAssetPaths.isEmpty
            || !missingDatabaseContentHashes.isEmpty
            || !corruptedStoredContentHashes.isEmpty
    }

    var isClean: Bool {
        !hasBlockingIssue
            && orphanStoredContentHashes.isEmpty
            && unpinnedUnlinkedAssetRecords.isEmpty
    }
}

struct CanonicalAssetCleanupResult: Sendable, Equatable {
    let removedContentHashes: [String]
    let reportBeforeCleanup: CanonicalAssetReachabilityReport
}

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

    func audit() throws -> CanonicalAssetReachabilityReport {
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

        let missingDatabaseContentHashes =
            databaseHashSet
            .subtracting(storedHashSet)
            .sorted()
        let orphanStoredContentHashes =
            storedHashSet
            .subtracting(databaseHashSet)
            .subtracting(Set(corruptedStoredContentHashes))
            .sorted()

        return try CanonicalAssetReachabilityReport(
            databaseReferences: databaseReferences(for: validDatabaseContentHashes),
            unlinkedAssetRecords: unlinkedAssetRecords(validContentHashes: databaseHashSet),
            storedContentHashes: listing.contentHashes,
            invalidDatabaseContentHashes: invalidDatabaseContentHashes.sorted(),
            invalidStoredAssetPaths: listing.invalidRelativePaths,
            missingDatabaseContentHashes: missingDatabaseContentHashes,
            corruptedStoredContentHashes: corruptedStoredContentHashes,
            orphanStoredContentHashes: orphanStoredContentHashes
        )
    }

    @discardableResult
    func cleanupOrphanBlobs() throws -> CanonicalAssetCleanupResult {
        try operationGate.performSync {
            try cleanupOrphanBlobsWithoutGate()
        }
    }

    private func cleanupOrphanBlobsWithoutGate() throws -> CanonicalAssetCleanupResult {
        let report = try audit()
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
