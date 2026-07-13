import GRDB
import XCTest
@testable import HeatMoment

final class RecoveryPointSnapshotServiceTests: XCTestCase {}

extension RecoveryPointSnapshotServiceTests {
    func testCreateRecoveryPointWritesRealSnapshotCatalogManifestAndPins() async throws {
        let fixture = try makeFixture()
        let tag = try await fixture.runtime.repository.createOrReuseTag(
            name: "旅行",
            now: Date(timeIntervalSince1970: 50)
        )
        _ = try await fixture.runtime.repository.createMoment(
            title: "第一条",
            bodyText: "正文",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .happy,
            tagIDs: [tag.id],
            now: Date(timeIntervalSince1970: 200)
        )
        let assetID = uuid("00000000-0000-0000-0000-000000001001")
        let assetData = Data([0xA1, 0xA2, 0xA3])
        let storedAsset = try fixture.runtime.assetStore.store(data: assetData)
        try insertAssetRecord(
            id: assetID,
            storedAsset: storedAsset,
            in: fixture.runtime.store
        )
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000001101")

        let result = try fixture.runtime.recoveryPointSnapshotService.createRecoveryPoint(
            RecoveryPointSnapshotRequest(
                id: recoveryPointID,
                reason: .stableChanges,
                createdAt: Date(timeIntervalSince1970: 300),
                appVersion: "1.0.8"
            )
        )

        let record = result.recoveryPoint
        let snapshotURL = fixture.rootDirectory.appendingPathComponent(
            record.sqliteSnapshot.relativePath
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))
        XCTAssertEqual(
            record.counts,
            CanonicalRecoveryPointCounts(
                recordCount: 1,
                tagCount: 1,
                assetCount: 1
            )
        )
        XCTAssertEqual(record.sqliteSnapshot.byteCount, try fileSize(snapshotURL))
        XCTAssertEqual(
            record.sqliteSnapshot.sha256,
            FileAssetStore.sha256Hex(try Data(contentsOf: snapshotURL))
        )
        XCTAssertEqual(
            record.sqliteSnapshot.relativePath,
            "RecoveryPoints/\(recoveryPointID.uuidString)/Library.sqlite"
        )
        XCTAssertEqual(try snapshotMomentTitles(in: snapshotURL), ["第一条"])

        let manifest = try fixture.runtime.recoveryPointStore.assetManifest(for: recoveryPointID)
        XCTAssertEqual(manifest.count, 1)
        XCTAssertEqual(manifest.first?.assetID, assetID)
        XCTAssertEqual(manifest.first?.contentHash, storedAsset.contentHash)
        XCTAssertEqual(
            manifest.first?.relativePath,
            "Assets/blobs/\(String(storedAsset.contentHash.prefix(2)))/\(storedAsset.contentHash)"
        )
        XCTAssertEqual(
            try recoveryPointPinCount(in: fixture.runtime.store, ownerID: recoveryPointID),
            1
        )
        let validated = try fixture.runtime.recoveryPointSnapshotService.validateRecoveryPoint(
            id: recoveryPointID
        )
        XCTAssertEqual(validated.status, .available)
    }

    func testSnapshotIsPointInTimeAndDoesNotIncludeLaterWrites() async throws {
        let fixture = try makeFixture()
        _ = try await fixture.runtime.repository.createMoment(
            title: "快照内",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .normal
        )
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000001201")
        let result = try fixture.runtime.recoveryPointSnapshotService.createRecoveryPoint(
            RecoveryPointSnapshotRequest(
                id: recoveryPointID,
                reason: .stableChanges,
                createdAt: Date(timeIntervalSince1970: 200),
                appVersion: "1.0.8"
            )
        )
        _ = try await fixture.runtime.repository.createMoment(
            title: "后续写入",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 300),
            mood: .sad
        )

        let snapshotURL = fixture.rootDirectory.appendingPathComponent(
            result.recoveryPoint.sqliteSnapshot.relativePath
        )
        XCTAssertEqual(try snapshotMomentTitles(in: snapshotURL), ["快照内"])
        XCTAssertEqual(try liveMomentCount(in: fixture.runtime.store), 2)
    }

    func testValidateMarksRecoveryPointInvalidWhenSnapshotHashChanges() async throws {
        let fixture = try makeFixture()
        _ = try await fixture.runtime.repository.createMoment(
            title: "会损坏",
            bodyText: "",
            occurredAt: .now,
            mood: .normal
        )
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000001301")
        let result = try fixture.runtime.recoveryPointSnapshotService.createRecoveryPoint(
            RecoveryPointSnapshotRequest(
                id: recoveryPointID,
                reason: .stableChanges,
                createdAt: .now,
                appVersion: "1.0.8"
            )
        )
        let snapshotURL = fixture.rootDirectory.appendingPathComponent(
            result.recoveryPoint.sqliteSnapshot.relativePath
        )
        var snapshotData = try Data(contentsOf: snapshotURL)
        snapshotData[0] = snapshotData[0] ^ 0xFF
        try snapshotData.write(to: snapshotURL, options: [.atomic])

        XCTAssertThrowsError(
            try fixture.runtime.recoveryPointSnapshotService.validateRecoveryPoint(
                id: recoveryPointID
            )
        ) { error in
            guard case RecoveryPointSnapshotServiceError.snapshotHashMismatch = error else {
                XCTFail("期望 snapshotHashMismatch，实际为 \(error)")
                return
            }
        }
        XCTAssertEqual(
            try fixture.runtime.recoveryPointStore.recoveryPoint(id: recoveryPointID)?.status,
            .invalid
        )
    }

    func testValidateMarksRecoveryPointInvalidWhenAssetBlobIsMissing() throws {
        let fixture = try makeFixture()
        let assetID = uuid("00000000-0000-0000-0000-000000001401")
        let storedAsset = try fixture.runtime.assetStore.store(data: Data([0xB1]))
        try insertAssetRecord(
            id: assetID,
            storedAsset: storedAsset,
            in: fixture.runtime.store
        )
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000001402")
        _ = try fixture.runtime.recoveryPointSnapshotService.createRecoveryPoint(
            RecoveryPointSnapshotRequest(
                id: recoveryPointID,
                reason: .stableChanges,
                createdAt: .now,
                appVersion: "1.0.8"
            )
        )
        try fixture.runtime.assetStore.removeBlob(forContentHash: storedAsset.contentHash)

        XCTAssertThrowsError(
            try fixture.runtime.recoveryPointSnapshotService.validateRecoveryPoint(
                id: recoveryPointID
            )
        ) { error in
            XCTAssertEqual(
                error as? RecoveryPointSnapshotServiceError,
                .missingAssetBlob(storedAsset.contentHash)
            )
        }
        XCTAssertEqual(
            try fixture.runtime.recoveryPointStore.recoveryPoint(id: recoveryPointID)?.status,
            .invalid
        )
    }

    func testValidateMarksRecoveryPointInvalidWhenCatalogCountsDriftFromSnapshot() async throws {
        let fixture = try makeFixture()
        _ = try await fixture.runtime.repository.createMoment(
            title: "计数漂移",
            bodyText: "",
            occurredAt: .now,
            mood: .normal
        )
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000001451")
        _ = try fixture.runtime.recoveryPointSnapshotService.createRecoveryPoint(
            RecoveryPointSnapshotRequest(
                id: recoveryPointID,
                reason: .stableChanges,
                createdAt: .now,
                appVersion: "1.0.8"
            )
        )
        try fixture.runtime.store.write { db in
            try db.execute(
                sql: "UPDATE recovery_point_record SET record_count = 0 WHERE id = ?",
                arguments: [recoveryPointID.uuidString]
            )
        }

        XCTAssertThrowsError(
            try fixture.runtime.recoveryPointSnapshotService.validateRecoveryPoint(
                id: recoveryPointID
            )
        ) { error in
            XCTAssertEqual(
                error as? RecoveryPointSnapshotServiceError,
                .catalogCountsMismatch(
                    expected: CanonicalRecoveryPointCounts(
                        recordCount: 0,
                        tagCount: 0,
                        assetCount: 0
                    ),
                    actual: CanonicalRecoveryPointCounts(
                        recordCount: 1,
                        tagCount: 0,
                        assetCount: 0
                    )
                )
            )
        }
        XCTAssertEqual(
            try fixture.runtime.recoveryPointStore.recoveryPoint(id: recoveryPointID)?.status,
            .invalid
        )
    }

    func testRetentionRemovesEvictedSnapshotDirectory() throws {
        let fixture = try makeFixture()
        let recoveryPointIDs = [
            uuid("00000000-0000-0000-0000-000000001501"),
            uuid("00000000-0000-0000-0000-000000001502"),
            uuid("00000000-0000-0000-0000-000000001503"),
            uuid("00000000-0000-0000-0000-000000001504"),
        ]

        for (index, id) in recoveryPointIDs.enumerated() {
            _ = try fixture.runtime.recoveryPointSnapshotService.createRecoveryPoint(
                RecoveryPointSnapshotRequest(
                    id: id,
                    reason: .stableChanges,
                    createdAt: Date(timeIntervalSince1970: Double(index)),
                    appVersion: "1.0.8"
                )
            )
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.descriptor.recoveryPointDirectoryURL
                    .appendingPathComponent(recoveryPointIDs[0].uuidString, isDirectory: true)
                    .path
            )
        )
        XCTAssertEqual(
            try fixture.runtime.recoveryPointStore.listRecoveryPoints().map(\.id),
            [recoveryPointIDs[3], recoveryPointIDs[2], recoveryPointIDs[1]]
        )
    }

    func testCatalogFailureRemovesSnapshotDirectory() throws {
        let fixture = try makeFixture()
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000001601")

        XCTAssertThrowsError(
            try fixture.runtime.recoveryPointSnapshotService.createRecoveryPoint(
                RecoveryPointSnapshotRequest(
                    id: recoveryPointID,
                    reason: .stableChanges,
                    createdAt: .now,
                    appVersion: ""
                )
            )
        ) { error in
            XCTAssertEqual(error as? CanonicalRecoveryPointStoreError, .emptyAppVersion)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.descriptor.recoveryPointDirectoryURL
                    .appendingPathComponent(recoveryPointID.uuidString, isDirectory: true)
                    .path
            )
        )
        XCTAssertTrue(try fixture.runtime.recoveryPointStore.listRecoveryPoints().isEmpty)
    }
}

private extension RecoveryPointSnapshotServiceTests {
    struct Fixture {
        let rootDirectory: URL
        let descriptor: CanonicalStoreDescriptor
        let runtime: CanonicalLibraryRuntime
    }

    func makeFixture() throws -> Fixture {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CanonicalRecoveryPointSnapshotServiceTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let descriptor = CanonicalStoreDescriptor(rootDirectory: rootDirectory)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        return try Fixture(
            rootDirectory: rootDirectory,
            descriptor: descriptor,
            runtime: CanonicalLibraryRuntime(descriptor: descriptor)
        )
    }

    func insertAssetRecord(
        id: UUID,
        storedAsset: StoredFileAsset,
        in store: CanonicalStore
    ) throws {
        try store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO asset_record (
                        id, content_hash, mime_type, byte_count, width, height,
                        created_at, reference_state, pin_count
                    ) VALUES (?, ?, ?, ?, NULL, NULL, ?, ?, ?)
                    """,
                arguments: [
                    id.uuidString,
                    storedAsset.contentHash,
                    "image/jpeg",
                    storedAsset.byteCount,
                    Date(timeIntervalSince1970: 100).timeIntervalSince1970,
                    "referenced",
                    0,
                ]
            )
        }
    }

    func snapshotMomentTitles(in snapshotURL: URL) throws -> [String] {
        let snapshotQueue = try DatabaseQueue(path: snapshotURL.path)
        return try snapshotQueue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT title FROM moment_record ORDER BY created_at ASC"
            )
        }
    }

    func liveMomentCount(in store: CanonicalStore) throws -> Int {
        try store.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM moment_record") ?? 0
        }
    }

    func recoveryPointPinCount(in store: CanonicalStore, ownerID: UUID) throws -> Int {
        try store.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM asset_pin_record
                    WHERE owner_kind = ? AND owner_id = ?
                    """,
                arguments: [
                    CanonicalAssetPinOwnerKind.recoveryPoint.rawValue,
                    ownerID.uuidString,
                ]
            ) ?? 0
        }
    }

    func fileSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
