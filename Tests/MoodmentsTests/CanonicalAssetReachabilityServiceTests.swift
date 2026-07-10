// swiftlint:disable file_length

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

    func testGarbageCollectionPlanReportsFinalizableRecordAndFutureBlob() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let stored = try fixture.assetStore.store(data: Data([0x37, 0x38]))
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

        let plan = try fixture.service.planGarbageCollection()

        XCTAssertFalse(plan.isBlocked)
        XCTAssertTrue(plan.hasWork)
        XCTAssertEqual(plan.finalizableAssetRecordIDs, [assetID])
        XCTAssertTrue(plan.currentOrphanBlobContentHashes.isEmpty)
        XCTAssertEqual(
            plan.futureRemovableBlobHashes,
            [stored.contentHash]
        )
        XCTAssertEqual(plan.removableBlobContentHashes, [stored.contentHash])
    }

    func testGarbageCollectionPlanIncludesCurrentOrphanBlob() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let orphan = try fixture.assetStore.store(data: Data([0x39, 0x3A]))

        let plan = try fixture.service.planGarbageCollection()

        XCTAssertFalse(plan.isBlocked)
        XCTAssertTrue(plan.hasWork)
        XCTAssertTrue(plan.finalizableAssetRecordIDs.isEmpty)
        XCTAssertEqual(plan.currentOrphanBlobContentHashes, [orphan.contentHash])
        XCTAssertTrue(plan.futureRemovableBlobHashes.isEmpty)
        XCTAssertEqual(plan.removableBlobContentHashes, [orphan.contentHash])
    }

    func testGarbageCollectionPlanKeepsPinnedCurrentOrphanBlob() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let orphan = try fixture.assetStore.store(data: Data([0x3A, 0x3B]))
        _ = try fixture.pinStore.pinContentHash(
            orphan.contentHash,
            ownerKind: .restoreStaging,
            ownerID: "restore-job",
            createdAt: Date(timeIntervalSince1970: 100)
        )

        let plan = try fixture.service.planGarbageCollection(
            now: Date(timeIntervalSince1970: 120)
        )

        XCTAssertFalse(plan.isBlocked)
        XCTAssertFalse(plan.hasWork)
        XCTAssertEqual(plan.report.activePinnedContentHashes, [orphan.contentHash])
        XCTAssertTrue(plan.currentOrphanBlobContentHashes.isEmpty)
        XCTAssertTrue(plan.removableBlobContentHashes.isEmpty)

        let cleanupResult = try fixture.service.cleanupOrphanBlobs(
            now: Date(timeIntervalSince1970: 120)
        )
        XCTAssertTrue(cleanupResult.removedContentHashes.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.fileURL.path))
    }

    func testGarbageCollectionPlanKeepsFutureBlobWhenContentHashHasActivePin() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let stored = try fixture.assetStore.store(data: Data([0x3B, 0x3C]))
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
        _ = try fixture.pinStore.pinContentHash(
            stored.contentHash,
            ownerKind: .exportJob,
            ownerID: "export-job",
            createdAt: Date(timeIntervalSince1970: 100)
        )

        let plan = try fixture.service.planGarbageCollection(
            now: Date(timeIntervalSince1970: 120)
        )

        XCTAssertFalse(plan.isBlocked)
        XCTAssertTrue(plan.hasWork)
        XCTAssertEqual(plan.finalizableAssetRecordIDs, [assetID])
        XCTAssertTrue(plan.futureRemovableBlobHashes.isEmpty)
        XCTAssertTrue(plan.removableBlobContentHashes.isEmpty)

        let finalization = try fixture.service.finalizeUnlinkedAssetRecords()
        XCTAssertEqual(finalization.deletedAssetRecordIDs, [assetID])
        let cleanupResult = try fixture.service.cleanupOrphanBlobs(
            now: Date(timeIntervalSince1970: 120)
        )
        XCTAssertTrue(cleanupResult.removedContentHashes.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.fileURL.path))
    }

    func testGarbageCollectionPlanIgnoresExpiredPin() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let orphan = try fixture.assetStore.store(data: Data([0x3D, 0x3E]))
        let pin = try fixture.pinStore.pinContentHash(
            orphan.contentHash,
            ownerKind: .sync,
            ownerID: "sync-lease",
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 110)
        )

        let plan = try fixture.service.planGarbageCollection(
            now: Date(timeIntervalSince1970: 120)
        )

        XCTAssertFalse(plan.isBlocked)
        XCTAssertEqual(plan.report.expiredAssetPinIDs, [pin.id])
        XCTAssertTrue(plan.report.activePinnedContentHashes.isEmpty)
        XCTAssertEqual(plan.currentOrphanBlobContentHashes, [orphan.contentHash])
        XCTAssertEqual(plan.removableBlobContentHashes, [orphan.contentHash])
    }

    func testFinalizeDeletesOnlyUnpinnedUnlinkedRecordsAndKeepsSharedBlob() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let stored = try fixture.assetStore.store(data: Data([0x3B, 0x3C]))
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
                pinCount: 0,
                db: db
            )
            try insertAssetLink(momentID: momentID, assetID: linkedAssetID, db: db)
        }

        let result = try fixture.service.finalizeUnlinkedAssetRecords()
        let reportAfterFinalization = try fixture.service.audit()

        XCTAssertEqual(result.deletedAssetRecordIDs, [unlinkedAssetID])
        XCTAssertEqual(result.planBeforeFinalization.finalizableAssetRecordIDs, [unlinkedAssetID])
        XCTAssertTrue(
            result.planBeforeFinalization
                .futureRemovableBlobHashes
                .isEmpty
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.fileURL.path))
        XCTAssertEqual(reportAfterFinalization.databaseReferences.first?.assetRecordCount, 1)
        XCTAssertTrue(reportAfterFinalization.isClean)
    }

    func testFinalizeKeepsPinnedUnlinkedRecord() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let stored = try fixture.assetStore.store(data: Data([0x3D, 0x3E]))
        let assetID = UUID()
        try fixture.store.write { db in
            try insertAssetRecord(
                id: assetID,
                contentHash: stored.contentHash,
                byteCount: stored.byteCount,
                pinCount: 1,
                db: db
            )
        }

        let result = try fixture.service.finalizeUnlinkedAssetRecords()
        let reportAfterFinalization = try fixture.service.audit()

        XCTAssertTrue(result.deletedAssetRecordIDs.isEmpty)
        XCTAssertTrue(result.planBeforeFinalization.finalizableAssetRecordIDs.isEmpty)
        XCTAssertEqual(reportAfterFinalization.unlinkedAssetRecords.map(\.assetID), [assetID])
        XCTAssertTrue(reportAfterFinalization.unpinnedUnlinkedAssetRecords.isEmpty)
        XCTAssertTrue(reportAfterFinalization.isClean)
    }

    func testFinalizeIsBlockedWhenAuditHasBlockingIssue() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let contentHash = FileAssetStore.sha256Hex(Data([0x3F]))
        let assetID = UUID()
        try fixture.store.write { db in
            try insertAssetRecord(
                id: assetID,
                contentHash: contentHash,
                byteCount: 1,
                pinCount: 0,
                db: db
            )
        }

        do {
            _ = try fixture.service.finalizeUnlinkedAssetRecords()
            XCTFail("期望存在 blocking issue 时阻断 finalization")
        } catch CanonicalAssetReachabilityError.finalizationBlocked(let plan) {
            XCTAssertEqual(plan.report.missingDatabaseContentHashes, [contentHash])
            XCTAssertEqual(plan.finalizableAssetRecordIDs, [assetID])
        } catch {
            XCTFail("期望 finalizationBlocked，实际抛出 \(error)")
        }
        XCTAssertEqual(try assetRecordCount(in: fixture.store), 1)
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

    func testAuditReportsInvalidNegativePinCount() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let stored = try fixture.assetStore.store(data: Data([0x41, 0x42]))
        let assetID = UUID()
        try fixture.store.write { db in
            try insertAssetRecord(
                id: assetID,
                contentHash: stored.contentHash,
                byteCount: stored.byteCount,
                pinCount: -1,
                db: db
            )
        }

        let report = try fixture.service.audit()

        XCTAssertFalse(report.isClean)
        XCTAssertTrue(report.hasBlockingIssue)
        XCTAssertEqual(report.invalidPinCountAssetRecordIDs, [assetID])
        XCTAssertTrue(report.unpinnedUnlinkedAssetRecords.isEmpty)

        do {
            _ = try fixture.service.finalizeUnlinkedAssetRecords()
            XCTFail("期望 negative pin_count 阻断 finalization")
        } catch CanonicalAssetReachabilityError.finalizationBlocked(let plan) {
            XCTAssertEqual(plan.report.invalidPinCountAssetRecordIDs, [assetID])
            XCTAssertTrue(plan.finalizableAssetRecordIDs.isEmpty)
        } catch {
            XCTFail("期望 finalizationBlocked，实际抛出 \(error)")
        }
        XCTAssertEqual(try assetRecordCount(in: fixture.store), 1)
    }

    func testAuditReportsInvalidAssetPinHashAsBlockingIssue() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        try fixture.store.write { db in
            try insertAssetPin(
                contentHash: "sha256-invalid",
                ownerKind: .recoveryPoint,
                ownerID: "recovery-1",
                createdAt: Date(timeIntervalSince1970: 100),
                expiresAt: nil,
                db: db
            )
        }

        let plan = try fixture.service.planGarbageCollection()

        XCTAssertTrue(plan.isBlocked)
        XCTAssertEqual(plan.report.invalidAssetPinContentHashes, ["sha256-invalid"])
        XCTAssertTrue(plan.removableBlobContentHashes.isEmpty)
    }

    func testAuditReportsInvalidAssetPinExpirationAsBlockingIssue() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let stored = try fixture.assetStore.store(data: Data([0x43, 0x44]))
        let pinID = UUID()
        try fixture.store.write { db in
            try insertAssetPin(
                id: pinID,
                contentHash: stored.contentHash,
                ownerKind: .exportJob,
                ownerID: "export-1",
                createdAt: Date(timeIntervalSince1970: 200),
                expiresAt: Date(timeIntervalSince1970: 100),
                db: db
            )
        }

        let plan = try fixture.service.planGarbageCollection()

        XCTAssertTrue(plan.isBlocked)
        XCTAssertEqual(plan.report.invalidAssetPinLeaseIDs, [pinID])
        XCTAssertEqual(plan.currentOrphanBlobContentHashes, [stored.contentHash])
    }

    func testAuditReportsMissingPinnedBlobAsBlockingIssue() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.assetDirectory) }
        let missingHash = String(repeating: "a", count: 64)
        _ = try fixture.pinStore.pinContentHash(
            missingHash,
            ownerKind: .restoreStaging,
            ownerID: "restore-missing",
            createdAt: Date(timeIntervalSince1970: 100)
        )

        let plan = try fixture.service.planGarbageCollection(
            now: Date(timeIntervalSince1970: 120)
        )

        XCTAssertTrue(plan.isBlocked)
        XCTAssertEqual(plan.report.activePinnedContentHashes, [missingHash])
        XCTAssertEqual(plan.report.missingPinnedContentHashes, [missingHash])
        XCTAssertTrue(plan.removableBlobContentHashes.isEmpty)
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
            pinStore: CanonicalAssetPinStore(store: store),
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

    // swiftlint:disable:next function_parameter_count
    private func insertAssetPin(
        id: UUID = UUID(),
        contentHash: String,
        ownerKind: CanonicalAssetPinOwnerKind,
        ownerID: String,
        createdAt: Date,
        expiresAt: Date?,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO asset_pin_record (
                    id, content_hash, owner_kind, owner_id, created_at, expires_at
                ) VALUES (?, ?, ?, ?, ?, ?)
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
    }

    private func assetRecordCount(in store: CanonicalStore) throws -> Int {
        try store.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM asset_record") ?? 0
        }
    }
}
// swiftlint:enable type_body_length

private struct Fixture {
    let store: CanonicalStore
    let assetStore: FileAssetStore
    let pinStore: CanonicalAssetPinStore
    let service: CanonicalAssetReachabilityService
    let assetDirectory: URL
}
