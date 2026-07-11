import GRDB
import XCTest
@testable import Moodments

final class CanonicalRestoreExecutorTests: XCTestCase {}

extension CanonicalRestoreExecutorTests {
    func testArmedPendingRestoreReplacesStoreAndPreservesCurrentLibraryIdentity() async throws {
        let fixture = try makeFixture()
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000002101")
        let currentLibraryID = uuid("00000000-0000-0000-0000-000000002102")
        let currentDeviceID = uuid("00000000-0000-0000-0000-000000002103")
        let restoredSyncEpoch = uuid("00000000-0000-0000-0000-000000002104")
        var context: CanonicalPendingRestoreContext?

        do {
            let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
            _ = try await runtime.repository.createMoment(
                title: "快照内",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 100),
                mood: .happy
            )
            _ = try runtime.recoveryPointSnapshotService.createRecoveryPoint(
                RecoveryPointSnapshotRequest(
                    id: recoveryPointID,
                    reason: .stableChanges,
                    createdAt: Date(timeIntervalSince1970: 200),
                    appVersion: "1.0.8"
                )
            )
            _ = try await runtime.repository.createMoment(
                title: "恢复前当前数据",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 300),
                mood: .sad
            )
            try updateLibraryIdentity(
                libraryID: currentLibraryID,
                deviceID: currentDeviceID,
                in: runtime.store
            )

            let executor = try CanonicalRestoreExecutor(runtime: runtime)
            let staged = try executor.stageRestore(
                recoveryPointID: recoveryPointID,
                restoreJobID: uuid("00000000-0000-0000-0000-000000002105"),
                restoredSyncEpoch: restoredSyncEpoch,
                now: Date(timeIntervalSince1970: 400)
            )
            try executor.armStagedRestore(context: staged)
            context = staged
        }

        try write(
            "stale-wal", to: URL(fileURLWithPath: fixture.descriptor.databaseURL.path + "-wal"))
        try write(
            "stale-shm", to: URL(fileURLWithPath: fixture.descriptor.databaseURL.path + "-shm"))
        let result = try CanonicalRestoreExecutor.performPendingRestoreIfNeeded(
            descriptor: fixture.descriptor,
            now: Date(timeIntervalSince1970: 500)
        )

        XCTAssertEqual(result, .restored(try XCTUnwrap(context)))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.descriptor.pendingRestoreDirectory.path
            ))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.descriptor.databaseURL.path + "-wal"
            ))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.descriptor.databaseURL.path + "-shm"
            ))

        let restoredRuntime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
        XCTAssertEqual(try momentTitles(in: restoredRuntime.store), ["快照内"])
        let metadata = try metadata(in: restoredRuntime.store)
        XCTAssertEqual(metadata.libraryID, currentLibraryID)
        XCTAssertEqual(metadata.deviceID, currentDeviceID)
        XCTAssertEqual(metadata.syncEpoch, restoredSyncEpoch)
    }

    func testUnarmedPendingRestoreDoesNotReplaceCurrentStoreAndReleasesStagingPins()
        async throws
    {
        let fixture = try makeFixture()
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000002201")
        var restoreJobID: UUID?

        do {
            let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
            let asset = try runtime.assetStore.store(data: Data([0xA1, 0xA2]))
            try insertAssetRecord(
                id: uuid("00000000-0000-0000-0000-000000002202"),
                storedAsset: asset,
                in: runtime.store
            )
            _ = try await runtime.repository.createMoment(
                title: "快照内",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 100),
                mood: .normal
            )
            _ = try runtime.recoveryPointSnapshotService.createRecoveryPoint(
                RecoveryPointSnapshotRequest(
                    id: recoveryPointID,
                    reason: .stableChanges,
                    createdAt: Date(timeIntervalSince1970: 200),
                    appVersion: "1.0.8"
                )
            )
            _ = try await runtime.repository.createMoment(
                title: "当前仍应保留",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 300),
                mood: .sad
            )

            let executor = try CanonicalRestoreExecutor(runtime: runtime)
            let context = try executor.stageRestore(recoveryPointID: recoveryPointID)
            restoreJobID = context.restoreJobID
            XCTAssertEqual(
                try pinCount(
                    in: runtime.store,
                    ownerKind: .restoreStaging,
                    ownerID: context.restoreJobID.uuidString
                ),
                1
            )
        }

        let result = try CanonicalRestoreExecutor.performPendingRestoreIfNeeded(
            descriptor: fixture.descriptor
        )

        XCTAssertEqual(result, .none)
        let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
        XCTAssertEqual(try momentTitles(in: runtime.store), ["快照内", "当前仍应保留"])
        XCTAssertEqual(
            try pinCount(
                in: runtime.store,
                ownerKind: .restoreStaging,
                ownerID: try XCTUnwrap(restoreJobID).uuidString
            ),
            0
        )
    }

    func testCorruptArmedPendingRestoreFailsAndReleasesPins() async throws {
        let fixture = try makeFixture()
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000002301")
        var context: CanonicalPendingRestoreContext?

        do {
            let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
            let asset = try runtime.assetStore.store(data: Data([0xB1]))
            try insertAssetRecord(
                id: uuid("00000000-0000-0000-0000-000000002302"),
                storedAsset: asset,
                in: runtime.store
            )
            _ = try await runtime.repository.createMoment(
                title: "快照内",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 100),
                mood: .normal
            )
            _ = try runtime.recoveryPointSnapshotService.createRecoveryPoint(
                RecoveryPointSnapshotRequest(
                    id: recoveryPointID,
                    reason: .stableChanges,
                    createdAt: Date(timeIntervalSince1970: 200),
                    appVersion: "1.0.8"
                )
            )
            _ = try await runtime.repository.createMoment(
                title: "当前数据",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 300),
                mood: .sad
            )

            let executor = try CanonicalRestoreExecutor(runtime: runtime)
            let staged = try executor.stageRestore(recoveryPointID: recoveryPointID)
            try executor.armStagedRestore(context: staged)
            context = staged
            try write("corrupt", to: pendingPayloadURL(descriptor: fixture.descriptor))
        }

        let result = try CanonicalRestoreExecutor.performPendingRestoreIfNeeded(
            descriptor: fixture.descriptor
        )

        XCTAssertNotNil(result.failure)
        XCTAssertEqual(result.failure?.context, context)
        let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
        XCTAssertEqual(try momentTitles(in: runtime.store), ["快照内", "当前数据"])
        XCTAssertEqual(
            try pinCount(
                in: runtime.store,
                ownerKind: .restoreStaging,
                ownerID: try XCTUnwrap(context?.restoreJobID).uuidString
            ),
            0
        )
    }

    func testMissingPendingContextDoesNotRestoreAndReleasesStagingPins() async throws {
        let fixture = try makeFixture()
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000002351")
        var restoreJobID: UUID?

        do {
            let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
            let asset = try runtime.assetStore.store(data: Data([0xC1]))
            try insertAssetRecord(
                id: uuid("00000000-0000-0000-0000-000000002352"),
                storedAsset: asset,
                in: runtime.store
            )
            _ = try await runtime.repository.createMoment(
                title: "快照内",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 100),
                mood: .normal
            )
            _ = try runtime.recoveryPointSnapshotService.createRecoveryPoint(
                RecoveryPointSnapshotRequest(
                    id: recoveryPointID,
                    reason: .stableChanges,
                    createdAt: Date(timeIntervalSince1970: 200),
                    appVersion: "1.0.8"
                )
            )

            let executor = try CanonicalRestoreExecutor(runtime: runtime)
            let context = try executor.stageRestore(recoveryPointID: recoveryPointID)
            restoreJobID = context.restoreJobID
            try FileManager.default.removeItem(
                at: pendingContextURL(descriptor: fixture.descriptor))
        }

        let result = try CanonicalRestoreExecutor.performPendingRestoreIfNeeded(
            descriptor: fixture.descriptor
        )

        XCTAssertEqual(result, .none)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.descriptor.pendingRestoreDirectory.path
            ))
        let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
        XCTAssertEqual(
            try pinCount(
                in: runtime.store,
                ownerKind: .restoreStaging,
                ownerID: try XCTUnwrap(restoreJobID).uuidString
            ),
            0
        )
        XCTAssertEqual(try momentTitles(in: runtime.store), ["快照内"])
    }

    func testCorruptPendingContextFailsAndReleasesStagingPins() async throws {
        let fixture = try makeFixture()
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000002361")
        var restoreJobID: UUID?

        do {
            let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
            let asset = try runtime.assetStore.store(data: Data([0xD1]))
            try insertAssetRecord(
                id: uuid("00000000-0000-0000-0000-000000002362"),
                storedAsset: asset,
                in: runtime.store
            )
            _ = try await runtime.repository.createMoment(
                title: "快照内",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 100),
                mood: .normal
            )
            _ = try runtime.recoveryPointSnapshotService.createRecoveryPoint(
                RecoveryPointSnapshotRequest(
                    id: recoveryPointID,
                    reason: .stableChanges,
                    createdAt: Date(timeIntervalSince1970: 200),
                    appVersion: "1.0.8"
                )
            )
            _ = try await runtime.repository.createMoment(
                title: "当前数据",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 300),
                mood: .sad
            )

            let executor = try CanonicalRestoreExecutor(runtime: runtime)
            let context = try executor.stageRestore(recoveryPointID: recoveryPointID)
            try executor.armStagedRestore(context: context)
            restoreJobID = context.restoreJobID
            try write("{", to: pendingContextURL(descriptor: fixture.descriptor))
        }

        let result = try CanonicalRestoreExecutor.performPendingRestoreIfNeeded(
            descriptor: fixture.descriptor
        )

        XCTAssertNotNil(result.failure)
        XCTAssertNil(result.failure?.context)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.descriptor.pendingRestoreDirectory.path
            ))
        let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
        XCTAssertEqual(try momentTitles(in: runtime.store), ["快照内", "当前数据"])
        XCTAssertEqual(
            try pinCount(
                in: runtime.store,
                ownerKind: .restoreStaging,
                ownerID: try XCTUnwrap(restoreJobID).uuidString
            ),
            0
        )
    }

    func testReplaceStorePayloadRollsBackCurrentStoreWhenIncomingCopyFails() async throws {
        let fixture = try makeFixture()
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000002371")

        do {
            let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
            _ = try await runtime.repository.createMoment(
                title: "快照内",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 100),
                mood: .normal
            )
            _ = try runtime.recoveryPointSnapshotService.createRecoveryPoint(
                RecoveryPointSnapshotRequest(
                    id: recoveryPointID,
                    reason: .stableChanges,
                    createdAt: Date(timeIntervalSince1970: 200),
                    appVersion: "1.0.8"
                )
            )
            _ = try await runtime.repository.createMoment(
                title: "当前数据",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 300),
                mood: .sad
            )

            let executor = try CanonicalRestoreExecutor(runtime: runtime)
            _ = try executor.stageRestore(recoveryPointID: recoveryPointID)
        }

        XCTAssertThrowsError(
            try CanonicalRestoreExecutor.replaceStorePayload(
                from: pendingPayloadDirectory(descriptor: fixture.descriptor),
                descriptor: fixture.descriptor,
                copyIncomingPayload: { _, _ in
                    throw InjectedCopyError.copyFailed
                }
            )
        ) { error in
            XCTAssertEqual(error as? InjectedCopyError, .copyFailed)
        }

        let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
        XCTAssertEqual(try momentTitles(in: runtime.store), ["快照内", "当前数据"])
        XCTAssertEqual(try rollbackDirectoryNames(in: fixture.rootDirectory), [])
    }

    func testReplaceStorePayloadThrowsCriticalErrorWhenRollbackFails() async throws {
        let fixture = try makeFixture()
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000002381")

        do {
            let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
            _ = try await runtime.repository.createMoment(
                title: "快照内",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 100),
                mood: .normal
            )
            _ = try runtime.recoveryPointSnapshotService.createRecoveryPoint(
                RecoveryPointSnapshotRequest(
                    id: recoveryPointID,
                    reason: .stableChanges,
                    createdAt: Date(timeIntervalSince1970: 200),
                    appVersion: "1.0.8"
                )
            )
            _ = try await runtime.repository.createMoment(
                title: "当前数据",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 300),
                mood: .sad
            )

            let executor = try CanonicalRestoreExecutor(runtime: runtime)
            _ = try executor.stageRestore(recoveryPointID: recoveryPointID)
        }

        XCTAssertThrowsError(
            try CanonicalRestoreExecutor.replaceStorePayload(
                from: pendingPayloadDirectory(descriptor: fixture.descriptor),
                descriptor: fixture.descriptor,
                copyIncomingPayload: { _, _ in
                    throw InjectedCopyError.copyFailed
                },
                rollbackStorePayload: { _, _, _, _ in
                    throw InjectedRollbackError.rollbackFailed
                }
            )
        ) { error in
            guard case CanonicalRestoreCriticalError.rollbackFailed(let rollbackError) = error
            else {
                XCTFail("期望 rollbackFailed，实际抛出 \(error)")
                return
            }
            XCTAssertEqual(rollbackError as? InjectedRollbackError, .rollbackFailed)
        }
    }

    func testStagedRestoreSurvivesSelectedRecoveryPointEviction() async throws {
        let fixture = try makeFixture()
        let selectedRecoveryPointID = uuid("00000000-0000-0000-0000-000000002401")
        var context: CanonicalPendingRestoreContext?

        do {
            let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
            _ = try await runtime.repository.createMoment(
                title: "最旧恢复点内容",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 100),
                mood: .happy
            )
            _ = try runtime.recoveryPointSnapshotService.createRecoveryPoint(
                RecoveryPointSnapshotRequest(
                    id: selectedRecoveryPointID,
                    reason: .stableChanges,
                    createdAt: Date(timeIntervalSince1970: 100),
                    appVersion: "1.0.8"
                )
            )
            let executor = try CanonicalRestoreExecutor(runtime: runtime)
            let staged = try executor.stageRestore(recoveryPointID: selectedRecoveryPointID)
            context = staged

            for index in 0..<3 {
                _ = try await runtime.repository.createMoment(
                    title: "淘汰触发 \(index)",
                    bodyText: "",
                    occurredAt: Date(timeIntervalSince1970: Double(200 + index)),
                    mood: .normal
                )
                _ = try runtime.recoveryPointSnapshotService.createRecoveryPoint(
                    RecoveryPointSnapshotRequest(
                        id: uuid("00000000-0000-0000-0000-0000000024\(10 + index)"),
                        reason: .stableChanges,
                        createdAt: Date(timeIntervalSince1970: Double(200 + index)),
                        appVersion: "1.0.8"
                    )
                )
            }

            XCTAssertNil(try runtime.recoveryPointStore.recoveryPoint(id: selectedRecoveryPointID))
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: fixture.descriptor.recoveryPointDirectoryURL
                        .appendingPathComponent(
                            selectedRecoveryPointID.uuidString, isDirectory: true
                        )
                        .path
                ))
            try executor.armStagedRestore(context: staged)
        }

        let result = try CanonicalRestoreExecutor.performPendingRestoreIfNeeded(
            descriptor: fixture.descriptor
        )

        XCTAssertEqual(result, .restored(try XCTUnwrap(context)))
        let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
        XCTAssertEqual(try momentTitles(in: runtime.store), ["最旧恢复点内容"])
    }

    func testReconcileRecoveryPointDirectoriesRemovesOrphansAndStaging() throws {
        let fixture = try makeFixture()
        let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000002501")
        _ = try runtime.recoveryPointSnapshotService.createRecoveryPoint(
            RecoveryPointSnapshotRequest(
                id: recoveryPointID,
                reason: .stableChanges,
                createdAt: Date(timeIntervalSince1970: 100),
                appVersion: "1.0.8"
            )
        )
        let orphanID = uuid("00000000-0000-0000-0000-000000002502")
        let orphanDirectory = fixture.descriptor.recoveryPointDirectoryURL
            .appendingPathComponent(orphanID.uuidString, isDirectory: true)
        let stagingDirectory = fixture.descriptor.recoveryPointDirectoryURL
            .appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(
            at: orphanDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: stagingDirectory, withIntermediateDirectories: true)

        let result = try runtime.recoveryPointSnapshotService.reconcileRecoveryPointDirectories()

        XCTAssertEqual(result.removedDirectoryNames, [orphanID.uuidString, "staging"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDirectory.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.descriptor.recoveryPointDirectoryURL
                    .appendingPathComponent(recoveryPointID.uuidString, isDirectory: true)
                    .path
            ))
    }
}

private extension CanonicalRestoreExecutorTests {
    enum InjectedCopyError: Error, Equatable {
        case copyFailed
    }

    enum InjectedRollbackError: Error, Equatable {
        case rollbackFailed
    }

    struct Fixture {
        let rootDirectory: URL
        let descriptor: CanonicalStoreDescriptor
    }

    func makeFixture() throws -> Fixture {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CanonicalRestoreExecutorTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let descriptor = CanonicalStoreDescriptor(rootDirectory: rootDirectory)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        return Fixture(rootDirectory: rootDirectory, descriptor: descriptor)
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

    func updateLibraryIdentity(
        libraryID: UUID,
        deviceID: UUID,
        in store: CanonicalStore
    ) throws {
        try store.write { db in
            try db.execute(
                sql: """
                    UPDATE library_metadata
                    SET library_id = ?, device_id = ?
                    WHERE id = 1
                    """,
                arguments: [libraryID.uuidString, deviceID.uuidString]
            )
        }
    }

    func momentTitles(in store: CanonicalStore) throws -> [String] {
        try store.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT title FROM moment_record ORDER BY created_at ASC"
            )
        }
    }

    func metadata(in store: CanonicalStore) throws -> CanonicalLibraryMetadata {
        try store.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM library_metadata WHERE id = 1")
            else {
                throw DatabaseError(message: "Missing library metadata")
            }
            return try CanonicalLibraryMetadata(
                libraryID: row.canonicalUUID("library_id"),
                schemaVersion: row["schema_version"],
                deviceID: row.canonicalUUID("device_id"),
                syncEpoch: row.canonicalUUID("sync_epoch"),
                createdAt: row.canonicalDate("created_at"),
                updatedAt: row.canonicalDate("updated_at"),
                swiftDataImportedAt: row.canonicalOptionalDate("swift_data_imported_at"),
                swiftDataImportSourceFingerprint: row["swift_data_import_source_fingerprint"]
            )
        }
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
                arguments: [ownerKind.rawValue, ownerID]
            ) ?? 0
        }
    }

    func pendingPayloadURL(descriptor: CanonicalStoreDescriptor) -> URL {
        pendingPayloadDirectory(descriptor: descriptor)
            .appendingPathComponent(descriptor.databaseURL.lastPathComponent)
    }

    func pendingPayloadDirectory(descriptor: CanonicalStoreDescriptor) -> URL {
        descriptor.pendingRestoreDirectory
            .appendingPathComponent("payload", isDirectory: true)
    }

    func pendingContextURL(descriptor: CanonicalStoreDescriptor) -> URL {
        descriptor.pendingRestoreDirectory
            .appendingPathComponent("context.json")
    }

    func rollbackDirectoryNames(in rootDirectory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        )
        .map(\.lastPathComponent)
        .filter { $0.hasPrefix("RestoreRollback-") }
        .sorted()
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
    }

    func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
