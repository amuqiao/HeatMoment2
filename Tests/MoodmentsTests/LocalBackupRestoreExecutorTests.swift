import SwiftData
import XCTest
@testable import Moodments

final class LocalBackupRestoreExecutorTests: RecoveryPointTestCase {
    func testPendingRestoreReplacesCurrentStorePayload() async throws {
        let libraryDirectory = try makeSourceDirectory()
        let descriptor = LocalBackupStoreDescriptor(
            rootDirectory: libraryDirectory,
            storeFileName: "Moodments.store",
            sourceLibraryID: "test-local"
        )
        let manager = try RecoveryPointManager(recoveryDirectory: descriptor.recoveryDirectory)

        try write("backup", to: descriptor.storeURL)
        try write("backup-wal", to: libraryDirectory.appendingPathComponent("Moodments.store-wal"))
        try write(
            "backup-asset",
            to: libraryDirectory.appendingPathComponent("Moodments.store_SUPPORT/External/blob")
        )
        let metadata = try await manager.createRecoveryPoint(
            from: descriptor.payloadSource(),
            reason: .stableChanges,
            counts: RecoveryPointCounts(recordCount: 1, tagCount: 0, assetCount: 1),
            schemaVersion: 1,
            appVersion: "1.0.0",
            sourceLibraryID: descriptor.sourceLibraryID,
            createdAt: Date(timeIntervalSince1970: 100)
        )

        try write("current", to: descriptor.storeURL)
        try write("current-wal", to: libraryDirectory.appendingPathComponent("Moodments.store-wal"))
        try FileManager.default.removeItem(
            at: libraryDirectory.appendingPathComponent("Moodments.store_SUPPORT")
        )

        try LocalBackupRestoreExecutor.stageRestore(metadata: metadata, descriptor: descriptor)
        try LocalBackupRestoreExecutor.armStagedRestore(metadata: metadata, descriptor: descriptor)
        let result = try LocalBackupRestoreExecutor.performPendingRestoreIfNeeded(
            descriptor: descriptor
        )

        XCTAssertRestored(result, selectedRecoveryPointID: metadata.id)
        XCTAssertEqual(try readText(from: descriptor.storeURL), "backup")
        XCTAssertEqual(
            try readText(from: libraryDirectory.appendingPathComponent("Moodments.store-wal")),
            "backup-wal"
        )
        XCTAssertEqual(
            try readText(
                from: libraryDirectory.appendingPathComponent(
                    "Moodments.store_SUPPORT/External/blob")),
            "backup-asset"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: descriptor.pendingRestoreDirectory.path)
        )
    }

    func testUnarmedPendingRestoreDoesNotReplaceCurrentStorePayload() async throws {
        let libraryDirectory = try makeSourceDirectory()
        let descriptor = LocalBackupStoreDescriptor(
            rootDirectory: libraryDirectory,
            storeFileName: "Moodments.store",
            sourceLibraryID: "test-local"
        )
        let manager = try RecoveryPointManager(recoveryDirectory: descriptor.recoveryDirectory)

        try write("backup", to: descriptor.storeURL)
        let metadata = try await manager.createRecoveryPoint(
            from: descriptor.payloadSource(),
            reason: .stableChanges,
            counts: RecoveryPointCounts(recordCount: 1, tagCount: 0, assetCount: 0),
            schemaVersion: 1,
            appVersion: "1.0.0",
            sourceLibraryID: descriptor.sourceLibraryID,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try write("current", to: descriptor.storeURL)

        try LocalBackupRestoreExecutor.stageRestore(metadata: metadata, descriptor: descriptor)
        let result = try LocalBackupRestoreExecutor.performPendingRestoreIfNeeded(
            descriptor: descriptor
        )

        XCTAssertEqual(result, .none)
        XCTAssertEqual(try readText(from: descriptor.storeURL), "current")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: descriptor.pendingRestoreDirectory.path)
        )
    }

    func testCorruptArmedPendingRestoreFailsAndClearsPendingPayload() async throws {
        let libraryDirectory = try makeSourceDirectory()
        let descriptor = LocalBackupStoreDescriptor(
            rootDirectory: libraryDirectory,
            storeFileName: "Moodments.store",
            sourceLibraryID: "test-local"
        )
        let manager = try RecoveryPointManager(recoveryDirectory: descriptor.recoveryDirectory)

        try write("backup", to: descriptor.storeURL)
        let metadata = try await manager.createRecoveryPoint(
            from: descriptor.payloadSource(),
            reason: .stableChanges,
            counts: RecoveryPointCounts(recordCount: 1, tagCount: 0, assetCount: 0),
            schemaVersion: 1,
            appVersion: "1.0.0",
            sourceLibraryID: descriptor.sourceLibraryID,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try write("current", to: descriptor.storeURL)

        try LocalBackupRestoreExecutor.stageRestore(metadata: metadata, descriptor: descriptor)
        try LocalBackupRestoreExecutor.armStagedRestore(metadata: metadata, descriptor: descriptor)
        try write(
            "corrupt",
            to: descriptor.pendingRestoreDirectory.appendingPathComponent(
                "payload/Moodments.store"
            )
        )

        let result = try LocalBackupRestoreExecutor.performPendingRestoreIfNeeded(
            descriptor: descriptor
        )

        XCTAssertNotNil(result.failure)
        XCTAssertEqual(try readText(from: descriptor.storeURL), "current")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: descriptor.pendingRestoreDirectory.path)
        )
    }

    func testPrepareRestoreStagesSelectedPayloadBeforeSafetyPointPruning() async throws {
        let libraryDirectory = try makeSourceDirectory()
        let descriptor = LocalBackupStoreDescriptor(
            rootDirectory: libraryDirectory,
            storeFileName: "Moodments.store",
            sourceLibraryID: "test-local"
        )
        let manager = try RecoveryPointManager(
            recoveryDirectory: descriptor.recoveryDirectory,
            maxRecoveryPoints: 3
        )
        var created: [RecoveryPointMetadata] = []

        for index in 0..<3 {
            try write("backup-\(index)", to: descriptor.storeURL)
            let metadata = try await manager.createRecoveryPoint(
                from: descriptor.payloadSource(),
                reason: .stableChanges,
                counts: RecoveryPointCounts(recordCount: index, tagCount: 0, assetCount: 0),
                schemaVersion: 1,
                appVersion: "1.0.0",
                sourceLibraryID: descriptor.sourceLibraryID,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
            created.append(metadata)
        }
        try write("current", to: descriptor.storeURL)

        let coordinator = LocalBackupCoordinator(
            descriptor: descriptor,
            recoveryPointManager: manager,
            countsRepository: RecoveryPointCountsRepository(
                modelContainer: try ModelContainerConfig.makeInMemoryContainer()
            ),
            appVersion: "1.0.0",
            schemaVersion: 1
        )

        try await coordinator.prepareRestore(id: created[0].id)
        let listedAfterPrepare = try await manager.listRecoveryPoints()
        XCTAssertFalse(listedAfterPrepare.contains { $0.id == created[0].id })

        let result = try LocalBackupRestoreExecutor.performPendingRestoreIfNeeded(
            descriptor: descriptor
        )

        XCTAssertRestored(result, selectedRecoveryPointID: created[0].id)
        XCTAssertEqual(try readText(from: descriptor.storeURL), "backup-0")
    }

    func testPrepareRestoreCreatesRestoreSafetyPointAndArmsPendingRestore() async throws {
        let libraryDirectory = try makeSourceDirectory()
        let descriptor = LocalBackupStoreDescriptor(
            rootDirectory: libraryDirectory,
            storeFileName: "Moodments.store",
            sourceLibraryID: "test-local"
        )
        let manager = try RecoveryPointManager(recoveryDirectory: descriptor.recoveryDirectory)

        try write("backup", to: descriptor.storeURL)
        let metadata = try await manager.createRecoveryPoint(
            from: descriptor.payloadSource(),
            reason: .stableChanges,
            counts: RecoveryPointCounts(recordCount: 1, tagCount: 0, assetCount: 0),
            schemaVersion: 1,
            appVersion: "1.0.0",
            sourceLibraryID: descriptor.sourceLibraryID,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try write("current", to: descriptor.storeURL)

        let coordinator = LocalBackupCoordinator(
            descriptor: descriptor,
            recoveryPointManager: manager,
            countsRepository: RecoveryPointCountsRepository(
                modelContainer: try ModelContainerConfig.makeInMemoryContainer()
            ),
            appVersion: "1.0.0",
            schemaVersion: 1
        )

        let context = try await coordinator.prepareRestore(id: metadata.id)

        let listed = try await manager.listRecoveryPoints()
        let restoreSafety = try XCTUnwrap(listed.first { $0.reason == .restoreSafety })
        XCTAssertEqual(context.selectedRecoveryPointID, metadata.id)
        XCTAssertEqual(context.restoreSafetyPointID, restoreSafety.id)
        let result = try LocalBackupRestoreExecutor.performPendingRestoreIfNeeded(
            descriptor: descriptor
        )
        XCTAssertRestored(
            result,
            selectedRecoveryPointID: metadata.id,
            restoreSafetyPointID: restoreSafety.id,
            checksRestoreSafetyPointID: true
        )
        XCTAssertEqual(try readText(from: descriptor.storeURL), "backup")
    }

    private func XCTAssertRestored(
        _ result: LocalBackupBootRestoreResult,
        selectedRecoveryPointID: UUID,
        restoreSafetyPointID: UUID? = nil,
        checksRestoreSafetyPointID: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .restored(context) = result else {
            XCTFail("Expected restored result, got \(result)", file: file, line: line)
            return
        }
        XCTAssertEqual(
            context.selectedRecoveryPointID,
            selectedRecoveryPointID,
            file: file,
            line: line
        )
        if checksRestoreSafetyPointID {
            XCTAssertEqual(
                context.restoreSafetyPointID,
                restoreSafetyPointID,
                file: file,
                line: line
            )
        }
    }

    private func readText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let string = String(bytes: data, encoding: .utf8) else {
            throw LocalBackupRestoreExecutorTestError.invalidUTF8
        }
        return string
    }
}

private enum LocalBackupRestoreExecutorTestError: Error {
    case invalidUTF8
}
