import Foundation

enum CanonicalAssetReachabilityError: Error, Equatable {
    case cleanupBlocked(CanonicalAssetReachabilityReport)
    case finalizationBlocked(CanonicalAssetGarbageCollectionPlan)
    case finalizationRace(expectedAssetRecordIDs: [UUID], deletedAssetRecordIDs: [UUID])
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
    let activePinnedContentHashes: [String]
    let expiredAssetPinIDs: [UUID]
    let storedContentHashes: [String]
    let invalidDatabaseContentHashes: [String]
    let invalidAssetPinContentHashes: [String]
    let invalidAssetPinLeaseIDs: [UUID]
    let invalidPinCountAssetRecordIDs: [UUID]
    let invalidStoredAssetPaths: [String]
    let missingDatabaseContentHashes: [String]
    let missingPinnedContentHashes: [String]
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
        Array(
            Set(databaseReferences.filter(\.isPinned).map(\.contentHash))
                .union(activePinnedContentHashes)
        )
        .sorted()
    }

    var unpinnedUnlinkedAssetRecords: [CanonicalUnlinkedAssetRecord] {
        unlinkedAssetRecords.filter { $0.pinCount == 0 }
    }

    var hasBlockingIssue: Bool {
        !invalidDatabaseContentHashes.isEmpty
            || !invalidAssetPinContentHashes.isEmpty
            || !invalidAssetPinLeaseIDs.isEmpty
            || !invalidPinCountAssetRecordIDs.isEmpty
            || !invalidStoredAssetPaths.isEmpty
            || !missingDatabaseContentHashes.isEmpty
            || !missingPinnedContentHashes.isEmpty
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

struct CanonicalAssetGarbageCollectionPlan: Sendable, Equatable {
    let report: CanonicalAssetReachabilityReport
    let finalizableAssetRecordIDs: [UUID]
    let currentOrphanBlobContentHashes: [String]
    let futureRemovableBlobHashes: [String]

    var removableBlobContentHashes: [String] {
        Array(
            Set(currentOrphanBlobContentHashes)
                .union(futureRemovableBlobHashes)
        )
        .sorted()
    }

    var isBlocked: Bool {
        report.hasBlockingIssue
    }

    var hasWork: Bool {
        !finalizableAssetRecordIDs.isEmpty || !removableBlobContentHashes.isEmpty
    }
}

struct CanonicalAssetRecordFinalizationResult: Sendable, Equatable {
    let deletedAssetRecordIDs: [UUID]
    let planBeforeFinalization: CanonicalAssetGarbageCollectionPlan
}
