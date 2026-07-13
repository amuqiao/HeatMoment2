import GRDB
import XCTest
@testable import HeatMoment

final class CanonicalBootRestoreGateTests: XCTestCase {}

extension CanonicalBootRestoreGateTests {
    func testGateReturnsNoneWithoutCreatingRuntimeWhenNoPendingRestore() throws {
        let fixture = makeFixture()

        let result = try CanonicalBootRestoreGate.performPendingRestoreIfNeeded(
            descriptor: fixture.descriptor
        )

        XCTAssertEqual(result, .none)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.rootDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.descriptor.databaseURL.path))
    }

    func testGateRestoresArmedPendingBeforeCallerOpensRuntime() async throws {
        let fixture = makeFixture()
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000003101")
        var expectedContext: CanonicalPendingRestoreContext?

        do {
            let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
            _ = try await runtime.repository.createMoment(
                title: "恢复点内容",
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
                title: "恢复前当前内容",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 300),
                mood: .sad
            )

            let executor = try CanonicalRestoreExecutor(runtime: runtime)
            let context = try executor.stageRestore(
                recoveryPointID: recoveryPointID,
                restoreJobID: uuid("00000000-0000-0000-0000-000000003102"),
                restoredSyncEpoch: uuid("00000000-0000-0000-0000-000000003103"),
                now: Date(timeIntervalSince1970: 400)
            )
            try executor.armStagedRestore(context: context)
            expectedContext = context
        }

        let result = try CanonicalBootRestoreGate.performPendingRestoreIfNeeded(
            descriptor: fixture.descriptor,
            now: Date(timeIntervalSince1970: 500)
        )
        let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)

        XCTAssertEqual(result, .restored(try XCTUnwrap(expectedContext)))
        XCTAssertEqual(try momentTitles(in: runtime.store), ["恢复点内容"])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.descriptor.pendingRestoreDirectory.path
            ))
    }

    func testGateClearsUnarmedPendingAndDoesNotReplaceCurrentStore() async throws {
        let fixture = makeFixture()
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000003201")

        do {
            let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
            _ = try await runtime.repository.createMoment(
                title: "恢复点内容",
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
                title: "当前内容",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 300),
                mood: .sad
            )

            let executor = try CanonicalRestoreExecutor(runtime: runtime)
            _ = try executor.stageRestore(recoveryPointID: recoveryPointID)
        }

        let result = try CanonicalBootRestoreGate.performPendingRestoreIfNeeded(
            descriptor: fixture.descriptor
        )
        let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)

        XCTAssertEqual(result, .none)
        XCTAssertEqual(try momentTitles(in: runtime.store), ["恢复点内容", "当前内容"])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.descriptor.pendingRestoreDirectory.path
            ))
    }

    func testGateFailsCorruptArmedPayloadWithoutReplacingStore() async throws {
        let fixture = makeFixture()
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000003301")
        var expectedContext: CanonicalPendingRestoreContext?

        do {
            let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
            _ = try await runtime.repository.createMoment(
                title: "恢复点内容",
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
                title: "当前内容",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 300),
                mood: .sad
            )

            let executor = try CanonicalRestoreExecutor(runtime: runtime)
            let context = try executor.stageRestore(recoveryPointID: recoveryPointID)
            try executor.armStagedRestore(context: context)
            expectedContext = context
            try write("corrupt", to: pendingPayloadURL(descriptor: fixture.descriptor))
        }

        let result = try CanonicalBootRestoreGate.performPendingRestoreIfNeeded(
            descriptor: fixture.descriptor
        )
        let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)

        XCTAssertEqual(result.failure?.context, expectedContext)
        XCTAssertEqual(try momentTitles(in: runtime.store), ["恢复点内容", "当前内容"])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.descriptor.pendingRestoreDirectory.path
            ))
    }

    func testGateThrowsCriticalErrorWhenRollbackFails() async throws {
        let fixture = makeFixture()
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000003401")

        do {
            let runtime = try CanonicalLibraryRuntime(descriptor: fixture.descriptor)
            _ = try await runtime.repository.createMoment(
                title: "恢复点内容",
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
                title: "当前内容",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 300),
                mood: .sad
            )

            let executor = try CanonicalRestoreExecutor(runtime: runtime)
            let context = try executor.stageRestore(recoveryPointID: recoveryPointID)
            try executor.armStagedRestore(context: context)
        }

        XCTAssertThrowsError(
            try CanonicalBootRestoreGate.performPendingRestoreIfNeeded(
                descriptor: fixture.descriptor,
                replaceStorePayload: { payloadDirectory, descriptor in
                    try CanonicalRestoreExecutor.replaceStorePayload(
                        from: payloadDirectory,
                        descriptor: descriptor,
                        copyIncomingPayload: { _, _ in
                            throw InjectedCopyError.copyFailed
                        },
                        rollbackStorePayload: { _, _, _, _ in
                            throw InjectedRollbackError.rollbackFailed
                        }
                    )
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
}

private extension CanonicalBootRestoreGateTests {
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

    func makeFixture() -> Fixture {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CanonicalBootRestoreGateTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let descriptor = CanonicalStoreDescriptor(rootDirectory: rootDirectory)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        return Fixture(rootDirectory: rootDirectory, descriptor: descriptor)
    }

    func momentTitles(in store: CanonicalStore) throws -> [String] {
        try store.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT title FROM moment_record ORDER BY created_at ASC"
            )
        }
    }

    func pendingPayloadURL(descriptor: CanonicalStoreDescriptor) -> URL {
        descriptor.pendingRestoreDirectory
            .appendingPathComponent("payload", isDirectory: true)
            .appendingPathComponent(descriptor.databaseURL.lastPathComponent)
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
