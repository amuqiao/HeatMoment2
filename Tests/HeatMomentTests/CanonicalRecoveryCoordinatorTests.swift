import GRDB
import XCTest
@testable import HeatMoment

final class CanonicalRecoveryCoordinatorTests: XCTestCase {}

extension CanonicalRecoveryCoordinatorTests {
    func testCreateRecoveryPointUsesCurrentCountsAndListsNewestFirst() async throws {
        let fixture = try makeFixture()
        let coordinator = CanonicalRecoveryCoordinator(
            runtime: fixture.runtime,
            appVersion: "1.0.8"
        )
        let tag = try await fixture.runtime.repository.createOrReuseTag(
            name: "工作",
            now: Date(timeIntervalSince1970: 50)
        )
        _ = try await fixture.runtime.repository.createMoment(
            title: "需要备份",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .happy,
            tagIDs: [tag.id],
            now: Date(timeIntervalSince1970: 120)
        )
        let asset = try fixture.runtime.assetStore.store(data: Data([0x01, 0x02]))
        try insertAssetRecord(
            id: uuid("00000000-0000-0000-0000-000000003101"),
            storedAsset: asset,
            in: fixture.runtime.store
        )

        let currentCounts = try await coordinator.currentCounts()
        let recoveryPoint = try await coordinator.createRecoveryPoint(
            id: uuid("00000000-0000-0000-0000-000000003102"),
            createdAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(
            currentCounts,
            CanonicalRecoveryPointCounts(recordCount: 1, tagCount: 1, assetCount: 1)
        )
        XCTAssertEqual(recoveryPoint.counts, currentCounts)
        XCTAssertEqual(recoveryPoint.reason, .stableChanges)
        XCTAssertEqual(recoveryPoint.appVersion, "1.0.8")
        let listedIDs = try await coordinator.listRecoveryPointIDs()
        XCTAssertEqual(listedIDs, [recoveryPoint.id])
    }

    func testStableChangesRecoveryPointIsThrottledByMinimumInterval() async throws {
        let fixture = try makeFixture()
        let coordinator = CanonicalRecoveryCoordinator(
            runtime: fixture.runtime,
            appVersion: "1.0.8",
            stableChangeMinimumInterval: 300
        )
        _ = try await fixture.runtime.repository.createMoment(
            title: "节流",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .normal
        )

        let first = try await coordinator.createStableChangesRecoveryPointIfNeeded(
            id: uuid("00000000-0000-0000-0000-000000003201"),
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let skipped = try await coordinator.createStableChangesRecoveryPointIfNeeded(
            id: uuid("00000000-0000-0000-0000-000000003202"),
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let second = try await coordinator.createStableChangesRecoveryPointIfNeeded(
            id: uuid("00000000-0000-0000-0000-000000003203"),
            createdAt: Date(timeIntervalSince1970: 600)
        )

        XCTAssertNotNil(first)
        XCTAssertNil(skipped)
        XCTAssertNotNil(second)
        let listedIDs = try await coordinator.listRecoveryPointIDs()
        XCTAssertEqual(
            listedIDs,
            [
                uuid("00000000-0000-0000-0000-000000003203"),
                uuid("00000000-0000-0000-0000-000000003201"),
            ])
    }

    func testStableChangesThrottleLoadsLatestPointAcrossCoordinatorInstances() async throws {
        let fixture = try makeFixture()
        let firstCoordinator = CanonicalRecoveryCoordinator(
            runtime: fixture.runtime,
            appVersion: "1.0.8",
            stableChangeMinimumInterval: 60
        )
        let restartedCoordinator = CanonicalRecoveryCoordinator(
            runtime: fixture.runtime,
            appVersion: "1.0.8",
            stableChangeMinimumInterval: 60
        )

        let first = try await firstCoordinator.createStableChangesRecoveryPointIfNeeded(
            id: uuid("00000000-0000-0000-0000-000000003251"),
            createdAt: Date(timeIntervalSince1970: 500)
        )
        let skippedAfterRestart =
            try await restartedCoordinator.createStableChangesRecoveryPointIfNeeded(
                id: uuid("00000000-0000-0000-0000-000000003252"),
                createdAt: Date(timeIntervalSince1970: 520)
            )
        let createdAfterWindow =
            try await restartedCoordinator.createStableChangesRecoveryPointIfNeeded(
                id: uuid("00000000-0000-0000-0000-000000003253"),
                createdAt: Date(timeIntervalSince1970: 561)
            )

        XCTAssertNotNil(first)
        XCTAssertNil(skippedAfterRestart)
        XCTAssertNotNil(createdAfterWindow)
        let listedIDs = try await restartedCoordinator.listRecoveryPointIDs()
        XCTAssertEqual(
            listedIDs,
            [
                uuid("00000000-0000-0000-0000-000000003253"),
                uuid("00000000-0000-0000-0000-000000003251"),
            ])
    }

    func testConcurrentStableChangesRequestsCreateOnlyOneRecoveryPoint() async throws {
        let fixture = try makeFixture()
        let coordinator = CanonicalRecoveryCoordinator(
            runtime: fixture.runtime,
            appVersion: "1.0.8",
            stableChangeMinimumInterval: 60
        )
        let createdAt = Date(timeIntervalSince1970: 600)
        let firstID = uuid("00000000-0000-0000-0000-000000003261")
        let secondID = uuid("00000000-0000-0000-0000-000000003262")

        async let first = coordinator.createStableChangesRecoveryPointIfNeeded(
            id: firstID,
            createdAt: createdAt
        )
        async let second = coordinator.createStableChangesRecoveryPointIfNeeded(
            id: secondID,
            createdAt: createdAt
        )

        let created = try await [first, second].compactMap { $0 }

        XCTAssertEqual(created.count, 1)
        let listed = try await coordinator.listRecoveryPoints()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.reason, .stableChanges)
    }

    func testMutationSafetyRecoveryPointBypassesStableChangesThrottle() async throws {
        let fixture = try makeFixture()
        let coordinator = CanonicalRecoveryCoordinator(
            runtime: fixture.runtime,
            appVersion: "1.0.8",
            stableChangeMinimumInterval: 60
        )

        let stable = try await coordinator.createStableChangesRecoveryPointIfNeeded(
            id: uuid("00000000-0000-0000-0000-000000003271"),
            createdAt: Date(timeIntervalSince1970: 400)
        )
        let safety = try await coordinator.createMutationSafetyRecoveryPoint(
            id: uuid("00000000-0000-0000-0000-000000003272"),
            createdAt: Date(timeIntervalSince1970: 401)
        )
        let skipped = try await coordinator.createStableChangesRecoveryPointIfNeeded(
            id: uuid("00000000-0000-0000-0000-000000003273"),
            createdAt: Date(timeIntervalSince1970: 402)
        )

        XCTAssertNotNil(stable)
        XCTAssertEqual(safety.reason, .mutationSafety)
        XCTAssertNil(skipped)
        let listed = try await coordinator.listRecoveryPoints()
        XCTAssertEqual(
            listed.map(\.id),
            [
                uuid("00000000-0000-0000-0000-000000003272"),
                uuid("00000000-0000-0000-0000-000000003271"),
            ])
        XCTAssertEqual(listed.map(\.reason), [.mutationSafety, .stableChanges])
    }

    func testPrepareRestoreCreatesRestoreSafetyPointAndArmsPendingRestore() async throws {
        let fixture = try makeFixture()
        let coordinator = CanonicalRecoveryCoordinator(
            runtime: fixture.runtime,
            appVersion: "1.0.8"
        )
        let selectedID = uuid("00000000-0000-0000-0000-000000003301")
        let restoreSafetyID = uuid("00000000-0000-0000-0000-000000003302")
        let restoreJobID = uuid("00000000-0000-0000-0000-000000003303")
        let restoredSyncEpoch = uuid("00000000-0000-0000-0000-000000003304")

        _ = try await fixture.runtime.repository.createMoment(
            title: "快照内容",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .happy
        )
        let selected = try await coordinator.createRecoveryPoint(
            id: selectedID,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        _ = try await fixture.runtime.repository.createMoment(
            title: "当前内容",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 300),
            mood: .sad
        )

        let prepared = try await coordinator.prepareRestore(
            id: selected.id,
            restoreJobID: restoreJobID,
            restoredSyncEpoch: restoredSyncEpoch,
            restoreSafetyID: restoreSafetyID,
            now: Date(timeIntervalSince1970: 400)
        )

        XCTAssertEqual(prepared.selectedRecoveryPoint.id, selectedID)
        XCTAssertEqual(prepared.restoreSafetyRecoveryPoint.id, restoreSafetyID)
        XCTAssertEqual(prepared.restoreSafetyRecoveryPoint.reason, .restoreSafety)
        XCTAssertEqual(prepared.pendingContext.restoreJobID, restoreJobID)
        XCTAssertEqual(prepared.pendingContext.restoredSyncEpoch, restoredSyncEpoch)
        XCTAssertEqual(
            prepared.retentionStatus,
            .completed(evictedRecoveryPointIDs: [])
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.descriptor.pendingRestoreDirectory
                    .appendingPathComponent("armed")
                    .path
            ))
        let listedIDs = try await coordinator.listRecoveryPointIDs()
        XCTAssertEqual(listedIDs, [restoreSafetyID, selectedID])
    }

    func testPrepareRestoreStagesSelectedBeforeRestoreSafetyEvictsOldestPoint() async throws {
        let fixture = try makeFixture()
        let coordinator = CanonicalRecoveryCoordinator(
            runtime: fixture.runtime,
            appVersion: "1.0.8"
        )
        let selectedID = uuid("00000000-0000-0000-0000-000000003351")
        let secondID = uuid("00000000-0000-0000-0000-000000003352")
        let thirdID = uuid("00000000-0000-0000-0000-000000003353")
        let restoreSafetyID = uuid("00000000-0000-0000-0000-000000003354")

        _ = try await coordinator.createRecoveryPoint(
            id: selectedID,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        _ = try await coordinator.createRecoveryPoint(
            id: secondID,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        _ = try await coordinator.createRecoveryPoint(
            id: thirdID,
            createdAt: Date(timeIntervalSince1970: 300)
        )

        let prepared = try await coordinator.prepareRestore(
            id: selectedID,
            restoreSafetyID: restoreSafetyID,
            now: Date(timeIntervalSince1970: 400)
        )

        XCTAssertEqual(prepared.selectedRecoveryPoint.id, selectedID)
        XCTAssertEqual(
            prepared.retentionStatus,
            .completed(evictedRecoveryPointIDs: [selectedID])
        )
        XCTAssertNil(try fixture.runtime.recoveryPointStore.recoveryPoint(id: selectedID))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.descriptor.pendingRestoreDirectory
                    .appendingPathComponent("payload", isDirectory: true)
                    .appendingPathComponent(fixture.descriptor.databaseURL.lastPathComponent)
                    .path
            ))
        let listedIDs = try await coordinator.listRecoveryPointIDs()
        XCTAssertEqual(listedIDs, [restoreSafetyID, thirdID, secondID])
    }

    func testPrepareRestoreRetentionFailureAfterArmReturnsPreparedRestore() async throws {
        let fixture = try makeFixture()
        let coordinator = CanonicalRecoveryCoordinator(
            runtime: fixture.runtime,
            appVersion: "1.0.8",
            enforceRecoveryPointRetention: { _ in
                throw InjectedRetentionError.failed
            }
        )
        let selectedID = uuid("00000000-0000-0000-0000-000000003371")
        let secondID = uuid("00000000-0000-0000-0000-000000003372")
        let thirdID = uuid("00000000-0000-0000-0000-000000003373")
        let restoreSafetyID = uuid("00000000-0000-0000-0000-000000003374")

        _ = try await coordinator.createRecoveryPoint(
            id: selectedID,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        _ = try await coordinator.createRecoveryPoint(
            id: secondID,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        _ = try await coordinator.createRecoveryPoint(
            id: thirdID,
            createdAt: Date(timeIntervalSince1970: 300)
        )

        let prepared = try await coordinator.prepareRestore(
            id: selectedID,
            restoreSafetyID: restoreSafetyID,
            now: Date(timeIntervalSince1970: 400)
        )

        XCTAssertEqual(prepared.selectedRecoveryPoint.id, selectedID)
        XCTAssertEqual(
            prepared.retentionStatus,
            .failedAfterRestoreArmed("failed")
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.descriptor.pendingRestoreDirectory
                    .appendingPathComponent("armed")
                    .path
            ))
        let listedIDs = try await coordinator.listRecoveryPointIDs()
        XCTAssertEqual(listedIDs, [restoreSafetyID, thirdID, secondID, selectedID])
    }

    func testPrepareRestoreArmFailureKeepsSelectedRecoveryPointRetryable() async throws {
        let fixture = try makeFixture()
        let coordinator = CanonicalRecoveryCoordinator(
            runtime: fixture.runtime,
            appVersion: "1.0.8",
            makeRestoreExecutor: { runtime in
                try FailingArmRestoreExecutor(runtime: runtime)
            }
        )
        let selectedID = uuid("00000000-0000-0000-0000-000000003361")
        let secondID = uuid("00000000-0000-0000-0000-000000003362")
        let thirdID = uuid("00000000-0000-0000-0000-000000003363")
        let restoreSafetyID = uuid("00000000-0000-0000-0000-000000003364")

        _ = try await coordinator.createRecoveryPoint(
            id: selectedID,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        _ = try await coordinator.createRecoveryPoint(
            id: secondID,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        _ = try await coordinator.createRecoveryPoint(
            id: thirdID,
            createdAt: Date(timeIntervalSince1970: 300)
        )

        do {
            try await coordinator.prepareRestore(
                id: selectedID,
                restoreSafetyID: restoreSafetyID,
                now: Date(timeIntervalSince1970: 400)
            )
            XCTFail("Expected arm failure to abort prepare restore.")
        } catch {
            XCTAssertEqual(error as? InjectedArmError, .failed)
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.descriptor.pendingRestoreDirectory.path
            ))
        XCTAssertNotNil(try fixture.runtime.recoveryPointStore.recoveryPoint(id: selectedID))
        XCTAssertNil(try fixture.runtime.recoveryPointStore.recoveryPoint(id: restoreSafetyID))
        let listedIDs = try await coordinator.listRecoveryPointIDs()
        XCTAssertEqual(listedIDs, [thirdID, secondID, selectedID])
    }

    func testPrepareRestoreRejectsIncompatibleRecoveryPointWithoutLeavingPendingRestore()
        async throws
    {
        let fixture = try makeFixture()
        let coordinator = CanonicalRecoveryCoordinator(
            runtime: fixture.runtime,
            appVersion: "1.0.8"
        )
        let selectedID = uuid("00000000-0000-0000-0000-000000003401")

        _ = try await fixture.runtime.repository.createMoment(
            title: "外来库",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .normal
        )
        _ = try await coordinator.createRecoveryPoint(
            id: selectedID,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        try updateLibraryIdentity(
            libraryID: uuid("00000000-0000-0000-0000-000000003402"),
            in: fixture.runtime.store
        )

        do {
            try await coordinator.prepareRestore(id: selectedID)
            XCTFail("Expected incompatible recovery point to be rejected.")
        } catch {
            XCTAssertEqual(
                error as? CanonicalRecoveryCoordinatorError,
                .incompatibleRecoveryPoint(selectedID)
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.descriptor.pendingRestoreDirectory.path
            ))
        let listedIDs = try await coordinator.listRecoveryPointIDs()
        XCTAssertEqual(listedIDs, [selectedID])
    }
}

private extension CanonicalRecoveryCoordinatorTests {
    enum InjectedArmError: Error, Equatable {
        case failed
    }

    enum InjectedRetentionError: Error, Equatable {
        case failed
    }

    struct FailingArmRestoreExecutor: CanonicalRestoreExecuting {
        let executor: CanonicalRestoreExecutor

        init(runtime: CanonicalLibraryRuntime) throws {
            executor = try CanonicalRestoreExecutor(runtime: runtime)
        }

        func stageRestore(
            recoveryPointID: UUID,
            restoreJobID: UUID,
            restoredSyncEpoch: UUID,
            now: Date
        ) throws -> CanonicalPendingRestoreContext {
            try executor.stageRestore(
                recoveryPointID: recoveryPointID,
                restoreJobID: restoreJobID,
                restoredSyncEpoch: restoredSyncEpoch,
                now: now
            )
        }

        func armStagedRestore(context: CanonicalPendingRestoreContext) throws {
            throw InjectedArmError.failed
        }

        func updateStagedRestoreContext(context: CanonicalPendingRestoreContext) throws {
            try executor.updateStagedRestoreContext(context: context)
        }

        func clearPendingRestore() throws {
            try executor.clearPendingRestore()
        }
    }

    struct Fixture {
        let rootDirectory: URL
        let descriptor: CanonicalStoreDescriptor
        let runtime: CanonicalLibraryRuntime
    }

    func makeFixture() throws -> Fixture {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CanonicalRecoveryCoordinatorTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let descriptor = CanonicalStoreDescriptor(rootDirectory: rootDirectory)
        let runtime = try CanonicalLibraryRuntime(descriptor: descriptor)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        return Fixture(
            rootDirectory: rootDirectory,
            descriptor: descriptor,
            runtime: runtime
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

    func updateLibraryIdentity(
        libraryID: UUID,
        in store: CanonicalStore
    ) throws {
        try store.write { db in
            try db.execute(
                sql: """
                    UPDATE library_metadata
                    SET library_id = ?
                    WHERE id = 1
                    """,
                arguments: [libraryID.uuidString]
            )
        }
    }

    func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}

private extension CanonicalRecoveryCoordinator {
    func listRecoveryPointIDs() throws -> [UUID] {
        try listRecoveryPoints().map(\.id)
    }
}
