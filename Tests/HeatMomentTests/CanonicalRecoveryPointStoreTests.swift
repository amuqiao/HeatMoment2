import GRDB
import XCTest
@testable import HeatMoment

final class CanonicalRecoveryPointStoreTests: XCTestCase {
    func testCreateRecoveryPointWritesCatalogManifestAndRecoveryPins() throws {
        let store = try CanonicalStore.makeInMemory()
        let recoveryStore = CanonicalRecoveryPointStore(store: store)
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000000101")
        let sourceLibraryID = uuid("00000000-0000-0000-0000-000000000201")
        let sharedContentHash = FileAssetStore.sha256Hex(Data([0x01, 0x02]))
        let firstAssetID = uuid("00000000-0000-0000-0000-000000000301")
        let secondAssetID = uuid("00000000-0000-0000-0000-000000000302")
        let manifest = [
            makeAssetRecord(
                recoveryPointID: recoveryPointID,
                assetID: secondAssetID,
                contentHash: sharedContentHash,
                byteCount: 20,
                relativePath: "Assets/blobs/aa/second"
            ),
            makeAssetRecord(
                recoveryPointID: recoveryPointID,
                assetID: firstAssetID,
                contentHash: sharedContentHash,
                byteCount: 10,
                relativePath: "Assets/blobs/aa/first"
            )
        ]

        let request = CanonicalRecoveryPointCreationRequest(
            id: recoveryPointID,
            reason: .stableChanges,
            createdAt: Date(timeIntervalSince1970: 100),
            schemaVersion: CanonicalStore.currentSchemaVersion,
            appVersion: "1.0.8",
            sourceLibraryID: sourceLibraryID,
            sqliteSnapshot: makeSnapshot(),
            counts: CanonicalRecoveryPointCounts(recordCount: 2, usedTagCount: 1, assetCount: 2),
            assetManifest: manifest
        )
        let result = try recoveryStore.createRecoveryPoint(request)

        XCTAssertTrue(result.evictedRecoveryPointIDs.isEmpty)
        XCTAssertEqual(result.recoveryPoint.id, recoveryPointID)
        XCTAssertEqual(try recoveryStore.listRecoveryPoints().map(\.id), [recoveryPointID])
        XCTAssertEqual(
            try recoveryStore.assetManifest(for: recoveryPointID).map(\.assetID),
            [firstAssetID, secondAssetID]
        )
        XCTAssertEqual(try pinCount(in: store, ownerID: recoveryPointID), 1)
        XCTAssertEqual(try recoveryPointCount(in: store), 1)
    }

    func testRetentionKeepsNewestThreeAndReleasesEvictedPins() throws {
        let store = try CanonicalStore.makeInMemory()
        let recoveryStore = CanonicalRecoveryPointStore(store: store)
        let pinStore = CanonicalAssetPinStore(store: store)
        let sourceLibraryID = uuid("00000000-0000-0000-0000-000000000401")
        let recoveryPointIDs = [
            uuid("00000000-0000-0000-0000-000000000501"),
            uuid("00000000-0000-0000-0000-000000000502"),
            uuid("00000000-0000-0000-0000-000000000503"),
            uuid("00000000-0000-0000-0000-000000000504")
        ]

        var latestResult: CanonicalRecoveryPointCreationResult?
        for (index, recoveryPointID) in recoveryPointIDs.enumerated() {
            let contentHash = FileAssetStore.sha256Hex(Data([UInt8(index)]))
            if index == 0 {
                try pinStore.pinContentHash(
                    contentHash,
                    ownerKind: .exportJob,
                    ownerID: "export-keeps-shared-hash"
                )
            }
            let counts = CanonicalRecoveryPointCounts(
                recordCount: index,
                usedTagCount: 0,
                assetCount: 1
            )
            let request = CanonicalRecoveryPointCreationRequest(
                id: recoveryPointID,
                reason: .stableChanges,
                createdAt: Date(timeIntervalSince1970: Double(100 + index)),
                schemaVersion: CanonicalStore.currentSchemaVersion,
                appVersion: "1.0.8",
                sourceLibraryID: sourceLibraryID,
                sqliteSnapshot: makeSnapshot(byte: UInt8(10 + index)),
                counts: counts,
                assetManifest: [
                    makeAssetRecord(
                        recoveryPointID: recoveryPointID,
                        assetID: uuid("00000000-0000-0000-0000-00000000060\(index)"),
                        contentHash: contentHash,
                        byteCount: 1,
                        relativePath: "Assets/blobs/\(index)/asset"
                    )
                ]
            )
            latestResult = try recoveryStore.createRecoveryPoint(request)
        }

        XCTAssertEqual(latestResult?.evictedRecoveryPointIDs, [recoveryPointIDs[0]])
        XCTAssertEqual(
            try recoveryStore.listRecoveryPoints().map(\.id),
            [recoveryPointIDs[3], recoveryPointIDs[2], recoveryPointIDs[1]]
        )
        XCTAssertTrue(try recoveryStore.assetManifest(for: recoveryPointIDs[0]).isEmpty)
        XCTAssertEqual(try pinCount(in: store, ownerID: recoveryPointIDs[0]), 0)
        XCTAssertEqual(
            try pinCount(in: store, ownerKind: .exportJob, ownerID: "export-keeps-shared-hash"),
            1
        )
        XCTAssertEqual(try totalRecoveryPointPinCount(in: store), 3)
        XCTAssertEqual(try recoveryPointCount(in: store), 3)
    }
}

final class CanonicalRecoveryPointValidationTests: XCTestCase {
    func testValidationRejectsEmptyAppVersionBeforeWriting() throws {
        let store = try CanonicalStore.makeInMemory()
        let recoveryStore = CanonicalRecoveryPointStore(store: store)
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000000701")
        let sourceLibraryID = uuid("00000000-0000-0000-0000-000000000702")
        let validAsset = makeAssetRecord(
            recoveryPointID: recoveryPointID,
            assetID: uuid("00000000-0000-0000-0000-000000000703"),
            contentHash: FileAssetStore.sha256Hex(Data([0x03])),
            byteCount: 1,
            relativePath: "Assets/blobs/03/blob"
        )

        let request = CanonicalRecoveryPointCreationRequest(
            id: recoveryPointID,
            reason: .stableChanges,
            createdAt: .now,
            schemaVersion: CanonicalStore.currentSchemaVersion,
            appVersion: "",
            sourceLibraryID: sourceLibraryID,
            sqliteSnapshot: makeSnapshot(),
            counts: oneAssetCounts,
            assetManifest: [validAsset]
        )

        XCTAssertThrowsError(
            try recoveryStore.createRecoveryPoint(request)
        ) { error in
            XCTAssertEqual(error as? CanonicalRecoveryPointStoreError, .emptyAppVersion)
        }

        XCTAssertEqual(try recoveryPointCount(in: store), 0)
        XCTAssertEqual(try totalRecoveryPointPinCount(in: store), 0)
    }

    func testValidationRejectsInvalidSnapshotPathBeforeWriting() throws {
        let store = try CanonicalStore.makeInMemory()
        let recoveryStore = CanonicalRecoveryPointStore(store: store)
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000000711")
        let sourceLibraryID = uuid("00000000-0000-0000-0000-000000000712")
        let validAsset = makeAssetRecord(
            recoveryPointID: recoveryPointID,
            assetID: uuid("00000000-0000-0000-0000-000000000713"),
            contentHash: FileAssetStore.sha256Hex(Data([0x03])),
            byteCount: 1,
            relativePath: "Assets/blobs/03/blob"
        )

        let request = CanonicalRecoveryPointCreationRequest(
            id: recoveryPointID,
            reason: .stableChanges,
            createdAt: .now,
            schemaVersion: CanonicalStore.currentSchemaVersion,
            appVersion: "1.0.8",
            sourceLibraryID: sourceLibraryID,
            sqliteSnapshot: CanonicalRecoveryPointSnapshot(
                relativePath: "../Library.sqlite",
                byteCount: 1,
                sha256: FileAssetStore.sha256Hex(Data([0x04]))
            ),
            counts: oneAssetCounts,
            assetManifest: [validAsset]
        )

        XCTAssertThrowsError(
            try recoveryStore.createRecoveryPoint(request)
        ) { error in
            XCTAssertEqual(
                error as? CanonicalRecoveryPointStoreError,
                .invalidSnapshotRelativePath("../Library.sqlite")
            )
        }

        XCTAssertEqual(try recoveryPointCount(in: store), 0)
        XCTAssertEqual(try totalRecoveryPointPinCount(in: store), 0)
    }

    func testValidationRejectsNegativeCountsBeforeWriting() throws {
        let store = try CanonicalStore.makeInMemory()
        let recoveryStore = CanonicalRecoveryPointStore(store: store)
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000000721")
        let sourceLibraryID = uuid("00000000-0000-0000-0000-000000000722")
        let validAsset = makeAssetRecord(
            recoveryPointID: recoveryPointID,
            assetID: uuid("00000000-0000-0000-0000-000000000723"),
            contentHash: FileAssetStore.sha256Hex(Data([0x03])),
            byteCount: 1,
            relativePath: "Assets/blobs/03/blob"
        )

        let request = CanonicalRecoveryPointCreationRequest(
            id: recoveryPointID,
            reason: .stableChanges,
            createdAt: .now,
            schemaVersion: CanonicalStore.currentSchemaVersion,
            appVersion: "1.0.8",
            sourceLibraryID: sourceLibraryID,
            sqliteSnapshot: makeSnapshot(),
            counts: CanonicalRecoveryPointCounts(recordCount: -1, usedTagCount: 0, assetCount: 1),
            assetManifest: [validAsset]
        )

        XCTAssertThrowsError(
            try recoveryStore.createRecoveryPoint(request)
        ) { error in
            XCTAssertEqual(
                error as? CanonicalRecoveryPointStoreError,
                .invalidCount(name: "recordCount", value: -1)
            )
        }

        XCTAssertEqual(try recoveryPointCount(in: store), 0)
        XCTAssertEqual(try totalRecoveryPointPinCount(in: store), 0)
    }

    func testValidationRejectsAssetCountMismatchBeforeWriting() throws {
        let store = try CanonicalStore.makeInMemory()
        let recoveryStore = CanonicalRecoveryPointStore(store: store)
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000000741")
        let sourceLibraryID = uuid("00000000-0000-0000-0000-000000000742")
        let validAsset = makeAssetRecord(
            recoveryPointID: recoveryPointID,
            assetID: uuid("00000000-0000-0000-0000-000000000743"),
            contentHash: FileAssetStore.sha256Hex(Data([0x03])),
            byteCount: 1,
            relativePath: "Assets/blobs/03/blob"
        )

        let request = CanonicalRecoveryPointCreationRequest(
            id: recoveryPointID,
            reason: .stableChanges,
            createdAt: .now,
            schemaVersion: CanonicalStore.currentSchemaVersion,
            appVersion: "1.0.8",
            sourceLibraryID: sourceLibraryID,
            sqliteSnapshot: makeSnapshot(),
            counts: CanonicalRecoveryPointCounts(recordCount: 1, usedTagCount: 0, assetCount: 2),
            assetManifest: [validAsset]
        )

        XCTAssertThrowsError(
            try recoveryStore.createRecoveryPoint(request)
        ) { error in
            XCTAssertEqual(
                error as? CanonicalRecoveryPointStoreError,
                .assetManifestCountMismatch(expected: 2, actual: 1)
            )
        }

        XCTAssertEqual(try recoveryPointCount(in: store), 0)
        XCTAssertEqual(try totalRecoveryPointPinCount(in: store), 0)
    }

    func testValidationRejectsInvalidAssetHashBeforeWriting() throws {
        let store = try CanonicalStore.makeInMemory()
        let recoveryStore = CanonicalRecoveryPointStore(store: store)
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000000731")
        let sourceLibraryID = uuid("00000000-0000-0000-0000-000000000732")
        let assetID = uuid("00000000-0000-0000-0000-000000000733")

        let request = CanonicalRecoveryPointCreationRequest(
            id: recoveryPointID,
            reason: .stableChanges,
            createdAt: .now,
            schemaVersion: CanonicalStore.currentSchemaVersion,
            appVersion: "1.0.8",
            sourceLibraryID: sourceLibraryID,
            sqliteSnapshot: makeSnapshot(),
            counts: oneAssetCounts,
            assetManifest: [
                makeAssetRecord(
                    recoveryPointID: recoveryPointID,
                    assetID: assetID,
                    contentHash: "invalid",
                    byteCount: 1,
                    relativePath: "Assets/blobs/03/blob"
                )
            ]
        )

        XCTAssertThrowsError(
            try recoveryStore.createRecoveryPoint(request)
        ) { error in
            XCTAssertEqual(
                error as? CanonicalRecoveryPointStoreError,
                .invalidAssetContentHash("invalid")
            )
        }

        XCTAssertEqual(try recoveryPointCount(in: store), 0)
        XCTAssertEqual(try totalRecoveryPointPinCount(in: store), 0)
    }

    func testValidationRejectsDuplicateAssetIDs() throws {
        let store = try CanonicalStore.makeInMemory()
        let recoveryStore = CanonicalRecoveryPointStore(store: store)
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000000801")
        let assetID = uuid("00000000-0000-0000-0000-000000000802")

        let request = CanonicalRecoveryPointCreationRequest(
            id: recoveryPointID,
            reason: .stableChanges,
            createdAt: .now,
            schemaVersion: CanonicalStore.currentSchemaVersion,
            appVersion: "1.0.8",
            sourceLibraryID: uuid("00000000-0000-0000-0000-000000000803"),
            sqliteSnapshot: makeSnapshot(),
            counts: CanonicalRecoveryPointCounts(recordCount: 1, usedTagCount: 0, assetCount: 2),
            assetManifest: [
                makeAssetRecord(
                    recoveryPointID: recoveryPointID,
                    assetID: assetID,
                    contentHash: FileAssetStore.sha256Hex(Data([0x05])),
                    byteCount: 1,
                    relativePath: "Assets/blobs/05/first"
                ),
                makeAssetRecord(
                    recoveryPointID: recoveryPointID,
                    assetID: assetID,
                    contentHash: FileAssetStore.sha256Hex(Data([0x06])),
                    byteCount: 1,
                    relativePath: "Assets/blobs/06/second"
                )
            ]
        )

        XCTAssertThrowsError(
            try recoveryStore.createRecoveryPoint(request)
        ) { error in
            XCTAssertEqual(
                error as? CanonicalRecoveryPointStoreError,
                .duplicateAssetID(assetID)
            )
        }
    }
}

fileprivate extension XCTestCase {
    var oneAssetCounts: CanonicalRecoveryPointCounts {
        CanonicalRecoveryPointCounts(recordCount: 1, usedTagCount: 0, assetCount: 1)
    }

    func makeSnapshot(byte: UInt8 = 0x09) -> CanonicalRecoveryPointSnapshot {
        CanonicalRecoveryPointSnapshot(
            relativePath: "RecoveryPoints/snapshot.sqlite",
            byteCount: 1,
            sha256: FileAssetStore.sha256Hex(Data([byte]))
        )
    }

    func makeAssetRecord(
        recoveryPointID: UUID,
        assetID: UUID,
        contentHash: String,
        byteCount: Int64,
        relativePath: String
    ) -> CanonicalRecoveryPointAssetRecord {
        CanonicalRecoveryPointAssetRecord(
            recoveryPointID: recoveryPointID,
            assetID: assetID,
            contentHash: contentHash,
            byteCount: byteCount,
            relativePath: relativePath
        )
    }

    func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    func recoveryPointCount(in store: CanonicalStore) throws -> Int {
        try store.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM recovery_point_record") ?? 0
        }
    }

    func pinCount(in store: CanonicalStore, ownerID: UUID) throws -> Int {
        try pinCount(in: store, ownerKind: .recoveryPoint, ownerID: ownerID.uuidString)
    }

    func pinCount(
        in store: CanonicalStore,
        ownerKind: CanonicalAssetPinOwnerKind,
        ownerID: String
    ) throws -> Int {
        try store.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM asset_pin_record
                    WHERE owner_kind = ? AND owner_id = ?
                    """,
                arguments: [
                    ownerKind.rawValue,
                    ownerID
                ]
            ) ?? 0
        }
    }

    func totalRecoveryPointPinCount(in store: CanonicalStore) throws -> Int {
        try store.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM asset_pin_record WHERE owner_kind = ?",
                arguments: [CanonicalAssetPinOwnerKind.recoveryPoint.rawValue]
            ) ?? 0
        }
    }
}
