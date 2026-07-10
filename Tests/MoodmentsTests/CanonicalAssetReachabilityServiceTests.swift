import GRDB
import XCTest
@testable import Moodments

// swiftlint:disable type_body_length
final class CanonicalAssetReachabilityServiceTests: XCTestCase {
    func testAuditReportsCleanLinkedAsset() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let data = Data([0x01, 0x02, 0x03])
        let stored = try fixture.assetStore.store(data: data)
        let momentID = UUID()
        let assetID = UUID()
        try fixture.store.write { db in
            try insertMoment(id: momentID, db: db)
            try insertAssetRecord(
                id: assetID,
                contentHash: stored.contentHash,
                byteCount: stored.byteCount,
                pinCount: 0,
                db: db
            )
            try insertAssetLink(momentID: momentID, assetID: assetID, db: db)
        }

        let report = try fixture.service.audit()

        XCTAssertTrue(report.isClean)
        XCTAssertEqual(report.databaseContentHashes, [stored.contentHash])
        XCTAssertEqual(report.linkedContentHashes, [stored.contentHash])
        XCTAssertEqual(report.storedContentHashes, [stored.contentHash])
        XCTAssertTrue(report.unlinkedAssetRecords.isEmpty)
        XCTAssertTrue(report.orphanStoredContentHashes.isEmpty)
        XCTAssertTrue(report.missingDatabaseContentHashes.isEmpty)
    }

    func testCleanupRemovesOnlyDatabaseOrphanBlobs() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let referencedData = Data([0x10, 0x11])
        let orphanData = Data([0x20, 0x21])
        let referenced = try fixture.assetStore.store(data: referencedData)
        let orphan = try fixture.assetStore.store(data: orphanData)
        let momentID = UUID()
        let assetID = UUID()
        try fixture.store.write { db in
            try insertMoment(id: momentID, db: db)
            try insertAssetRecord(
                id: assetID,
                contentHash: referenced.contentHash,
                byteCount: referenced.byteCount,
                pinCount: 0,
                db: db
            )
            try insertAssetLink(momentID: momentID, assetID: assetID, db: db)
        }

        let result = try fixture.service.cleanupOrphanBlobs()
        let reportAfterCleanup = try fixture.service.audit()

        XCTAssertEqual(result.removedContentHashes, [orphan.contentHash])
        XCTAssertTrue(FileManager.default.fileExists(atPath: referenced.fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.fileURL.path))
        XCTAssertTrue(reportAfterCleanup.isClean)
    }

    func testCleanupKeepsSharedContentHashWhenAnyAssetRecordReferencesIt() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let stored = try fixture.assetStore.store(data: Data([0x30, 0x31]))
        let linkedAssetID = UUID()
        let unlinkedAssetID = UUID()
        let momentID = UUID()
        try fixture.store.write { db in
            try insertMoment(id: momentID, db: db)
            try insertAssetRecord(
                id: linkedAssetID,
                contentHash: stored.contentHash,
                byteCount: stored.byteCount,
                pinCount: 0,
                db: db
            )
            try insertAssetRecord(
                id: unlinkedAssetID,
                contentHash: stored.contentHash,
                byteCount: stored.byteCount,
                pinCount: 2,
                db: db
            )
            try insertAssetLink(momentID: momentID, assetID: linkedAssetID, db: db)
        }

        let result = try fixture.service.cleanupOrphanBlobs()
        let reportAfterCleanup = try fixture.service.audit()

        XCTAssertTrue(result.removedContentHashes.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.fileURL.path))
        XCTAssertEqual(reportAfterCleanup.databaseReferences.first?.assetRecordCount, 2)
        XCTAssertEqual(reportAfterCleanup.pinnedContentHashes, [stored.contentHash])
        XCTAssertEqual(reportAfterCleanup.unlinkedAssetRecords.map(\.assetID), [unlinkedAssetID])
        XCTAssertTrue(reportAfterCleanup.unpinnedUnlinkedAssetRecords.isEmpty)
        XCTAssertTrue(reportAfterCleanup.isClean)
    }

    func testAuditReportsUnpinnedUnlinkedAssetRecord() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let stored = try fixture.assetStore.store(data: Data([0x35, 0x36]))
        let assetID = UUID()
        try fixture.store.write { db in
            try insertAssetRecord(
                id: assetID,
                contentHash: stored.contentHash,
                byteCount: stored.byteCount,
                pinCount: 0,
                db: db
            )
        }

        let report = try fixture.service.audit()

        XCTAssertFalse(report.isClean)
        XCTAssertEqual(report.unpinnedUnlinkedAssetRecords.map(\.assetID), [assetID])
        XCTAssertTrue(report.orphanStoredContentHashes.isEmpty)
        XCTAssertTrue(report.missingDatabaseContentHashes.isEmpty)
    }

    func testAuditReportsMissingDatabaseReferencedBlob() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let contentHash = FileAssetStore.sha256Hex(Data([0x40]))
        let momentID = UUID()
        let assetID = UUID()
        try fixture.store.write { db in
            try insertMoment(id: momentID, db: db)
            try insertAssetRecord(
                id: assetID,
                contentHash: contentHash,
                byteCount: 1,
                pinCount: 0,
                db: db
            )
            try insertAssetLink(momentID: momentID, assetID: assetID, db: db)
        }

        let report = try fixture.service.audit()

        XCTAssertFalse(report.isClean)
        XCTAssertEqual(report.missingDatabaseContentHashes, [contentHash])
        XCTAssertTrue(report.orphanStoredContentHashes.isEmpty)
    }

    func testAuditReportsInvalidDatabaseContentHash() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        try fixture.store.write { db in
            try insertAssetRecord(
                id: UUID(),
                contentHash: "sha256-invalid",
                byteCount: 1,
                pinCount: 0,
                db: db
            )
        }

        let report = try fixture.service.audit()

        XCTAssertFalse(report.isClean)
        XCTAssertEqual(report.invalidDatabaseContentHashes, ["sha256-invalid"])
        XCTAssertTrue(report.missingDatabaseContentHashes.isEmpty)
    }

    func testAuditReportsInvalidStoredAssetPath() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let invalidDirectory = fixture.assetDirectory
            .appendingPathComponent("blobs", isDirectory: true)
            .appendingPathComponent("zz", isDirectory: true)
        try FileManager.default.createDirectory(
            at: invalidDirectory,
            withIntermediateDirectories: true
        )
        let invalidURL = invalidDirectory.appendingPathComponent("not-a-sha256")
        try Data([0x60]).write(to: invalidURL, options: [.atomic])

        let report = try fixture.service.audit()

        XCTAssertFalse(report.isClean)
        XCTAssertEqual(report.invalidStoredAssetPaths, ["blobs/zz/not-a-sha256"])
        XCTAssertTrue(report.orphanStoredContentHashes.isEmpty)
    }

    func testCleanupIsBlockedWhenStoredBlobIsCorrupted() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let stored = try fixture.assetStore.store(data: Data([0x70, 0x71]))
        try Data([0x72]).write(to: stored.fileURL, options: [.atomic])

        do {
            _ = try fixture.service.cleanupOrphanBlobs()
            XCTFail("期望存在 corrupt blob 时阻断 cleanup")
        } catch CanonicalAssetReachabilityError.cleanupBlocked(let report) {
            XCTAssertEqual(report.corruptedStoredContentHashes, [stored.contentHash])
            XCTAssertTrue(report.orphanStoredContentHashes.isEmpty)
        } catch {
            XCTFail("期望 cleanupBlocked，实际抛出 \(error)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.fileURL.path))
    }

    func testCleanupIsBlockedWhenReferencedBlobIsMissing() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let contentHash = FileAssetStore.sha256Hex(Data([0x50]))
        let orphan = try fixture.assetStore.store(data: Data([0x51]))
        let momentID = UUID()
        let assetID = UUID()
        try fixture.store.write { db in
            try insertMoment(id: momentID, db: db)
            try insertAssetRecord(
                id: assetID,
                contentHash: contentHash,
                byteCount: 1,
                pinCount: 0,
                db: db
            )
            try insertAssetLink(momentID: momentID, assetID: assetID, db: db)
        }

        do {
            _ = try fixture.service.cleanupOrphanBlobs()
            XCTFail("期望存在 missing referenced blob 时阻断 cleanup")
        } catch CanonicalAssetReachabilityError.cleanupBlocked(let report) {
            XCTAssertEqual(report.missingDatabaseContentHashes, [contentHash])
            XCTAssertEqual(report.orphanStoredContentHashes, [orphan.contentHash])
        } catch {
            XCTFail("期望 cleanupBlocked，实际抛出 \(error)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.fileURL.path))
    }

    func testRuntimesForSameAssetRootShareOperationGate() throws {
        let assetDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CanonicalAssetOperationGateTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: assetDirectory) }

        let firstRuntime = try CanonicalLibraryRuntime.makeInMemoryForTests(
            assetDirectoryURL: assetDirectory
        )
        let secondRuntime = try CanonicalLibraryRuntime.makeInMemoryForTests(
            assetDirectoryURL: assetDirectory
        )

        XCTAssertTrue(firstRuntime.assetOperationGate === secondRuntime.assetOperationGate)
    }

    private func makeFixture() throws -> Fixture {
        let store = try CanonicalStore.makeInMemory()
        let assetDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CanonicalAssetReachabilityServiceTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let assetStore = FileAssetStore(rootDirectory: assetDirectory)
        let service = CanonicalAssetReachabilityService(store: store, assetStore: assetStore)
        return Fixture(
            store: store,
            assetStore: assetStore,
            service: service,
            assetDirectory: assetDirectory
        )
    }

    private func insertMoment(id: UUID, db: Database) throws {
        let now = Date(timeIntervalSince1970: 100).timeIntervalSince1970
        try db.execute(
            sql: """
                INSERT INTO moment_record (
                    id, title, body_text, occurred_at, created_at, updated_at,
                    mood_raw_value, lifecycle_state, deleted_at, purged_at, revision
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?)
                """,
            arguments: [
                id.uuidString,
                "有照片的时刻",
                "",
                now,
                now,
                now,
                Mood.normal.rawValue,
                CanonicalMomentLifecycleState.active.rawValue,
                // swiftlint:disable:next trailing_comma
                1,
            ]
        )
    }

    private func insertAssetRecord(
        id: UUID,
        contentHash: String,
        byteCount: Int,
        pinCount: Int,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO asset_record (
                    id, content_hash, mime_type, byte_count, width, height, created_at,
                    reference_state, pin_count
                ) VALUES (?, ?, ?, ?, NULL, NULL, ?, ?, ?)
                """,
            arguments: [
                id.uuidString,
                contentHash,
                "image/jpeg",
                byteCount,
                Date(timeIntervalSince1970: 100).timeIntervalSince1970,
                "referenced",
                // swiftlint:disable:next trailing_comma
                pinCount,
            ]
        )
    }

    private func insertAssetLink(
        momentID: UUID,
        assetID: UUID,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO moment_asset_link (moment_id, asset_id, sort_index, created_at)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [
                momentID.uuidString,
                assetID.uuidString,
                0,
                // swiftlint:disable:next trailing_comma
                Date(timeIntervalSince1970: 100).timeIntervalSince1970,
            ]
        )
    }
}
// swiftlint:enable type_body_length

private struct Fixture {
    let store: CanonicalStore
    let assetStore: FileAssetStore
    let service: CanonicalAssetReachabilityService
    let assetDirectory: URL
}
