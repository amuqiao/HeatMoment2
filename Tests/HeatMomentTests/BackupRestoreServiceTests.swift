import XCTest
@testable import HeatMoment

final class BackupRestoreServiceTests: XCTestCase {
    func testCanonicalRecoveryPointRecordMapsToBackupRecoveryPoint() {
        let id = uuid("00000000-0000-0000-0000-000000006201")
        let record = canonicalRecord(
            id: id,
            reason: .restoreSafety,
            status: .available,
            counts: CanonicalRecoveryPointCounts(recordCount: 5, tagCount: 6, assetCount: 7)
        )

        let point = BackupRecoveryPoint(record: record)

        XCTAssertEqual(point.id, id)
        XCTAssertEqual(point.reason, .restoreSafety)
        XCTAssertEqual(point.status, .available)
        XCTAssertEqual(
            point.counts,
            BackupRecoveryCounts(recordCount: 5, tagCount: 6, assetCount: 7)
        )
    }

    func testCanonicalPreparedRestoreMapsToBackupPendingContext() {
        let selected = canonicalRecord(
            id: uuid("00000000-0000-0000-0000-000000006401"),
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let restoreSafety = canonicalRecord(
            id: uuid("00000000-0000-0000-0000-000000006402"),
            createdAt: Date(timeIntervalSince1970: 400)
        )
        let prepared = CanonicalPreparedRestore(
            selectedRecoveryPoint: selected,
            restoreSafetyRecoveryPoint: restoreSafety,
            pendingContext: canonicalPendingContext(selected: selected),
            retentionStatus: .completed(evictedRecoveryPointIDs: [])
        )

        let context = BackupPendingRestoreContext(preparedRestore: prepared)

        XCTAssertEqual(context.selectedRecoveryPointID, selected.id)
        XCTAssertEqual(context.selectedCreatedAt, selected.createdAt)
        XCTAssertEqual(context.restoreSafetyPointID, restoreSafety.id)
        XCTAssertEqual(context.restoreSafetyCreatedAt, restoreSafety.createdAt)
    }

    func testCanonicalBootRestoreResultMapsToBackupBootRestoreResult() {
        let selected = canonicalRecord(
            id: uuid("00000000-0000-0000-0000-000000006601"),
            createdAt: Date(timeIntervalSince1970: 500)
        )
        let pendingContext = canonicalPendingContext(selected: selected)

        let result = BackupBootRestoreResult(
            result: CanonicalBootRestoreResult.restored(pendingContext))

        XCTAssertEqual(
            result,
            .restored(
                BackupPendingRestoreContext(
                    selectedRecoveryPointID: selected.id,
                    selectedCreatedAt: selected.createdAt,
                    restoreSafetyPointID: nil,
                    restoreSafetyCreatedAt: nil
                )
            )
        )
    }

    private func canonicalRecord(
        id: UUID,
        createdAt: Date = Date(timeIntervalSince1970: 100),
        reason: CanonicalRecoveryPointReason = .stableChanges,
        status: CanonicalRecoveryPointStatus = .available,
        counts: CanonicalRecoveryPointCounts = CanonicalRecoveryPointCounts(
            recordCount: 1,
            tagCount: 0,
            assetCount: 0
        )
    ) -> CanonicalRecoveryPointRecord {
        CanonicalRecoveryPointRecord(
            id: id,
            createdAt: createdAt,
            reason: reason,
            status: status,
            schemaVersion: CanonicalStore.currentSchemaVersion,
            appVersion: "1.0.8",
            sourceLibraryID: uuid("00000000-0000-0000-0000-000000006999"),
            sqliteSnapshot: CanonicalRecoveryPointSnapshot(
                relativePath: "RecoveryPoints/\(id.uuidString)/Library.sqlite",
                byteCount: 1,
                sha256: String(repeating: "a", count: 64)
            ),
            counts: counts
        )
    }

    private func canonicalPendingContext(
        selected: CanonicalRecoveryPointRecord
    ) -> CanonicalPendingRestoreContext {
        CanonicalPendingRestoreContext(
            restoreJobID: uuid("00000000-0000-0000-0000-000000006501"),
            selectedRecoveryPointID: selected.id,
            selectedCreatedAt: selected.createdAt,
            currentLibraryID: uuid("00000000-0000-0000-0000-000000006502"),
            currentDeviceID: uuid("00000000-0000-0000-0000-000000006503"),
            currentLibraryCreatedAt: Date(timeIntervalSince1970: 50),
            restoredSyncEpoch: uuid("00000000-0000-0000-0000-000000006504"),
            schemaVersion: selected.schemaVersion,
            appVersion: selected.appVersion,
            snapshot: CanonicalPendingRestoreSnapshot(
                relativePath: selected.sqliteSnapshot.relativePath,
                byteCount: selected.sqliteSnapshot.byteCount,
                sha256: selected.sqliteSnapshot.sha256
            ),
            counts: CanonicalPendingRestoreCounts(
                recordCount: selected.counts.recordCount,
                tagCount: selected.counts.tagCount,
                assetCount: selected.counts.assetCount
            ),
            assetManifest: []
        )
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
