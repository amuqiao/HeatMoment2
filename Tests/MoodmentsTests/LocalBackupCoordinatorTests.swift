import SwiftData
import XCTest
@testable import Moodments

final class LocalBackupCoordinatorTests: RecoveryPointTestCase {
    func testStoreDescriptorIncludesOnlyLocalSwiftDataPayload() async throws {
        let libraryDirectory = try makeSourceDirectory()
        let descriptor = LocalBackupStoreDescriptor(
            rootDirectory: libraryDirectory,
            storeFileName: "Moodments.store",
            sourceLibraryID: "test-local"
        )

        try write("store", to: libraryDirectory.appendingPathComponent("Moodments.store"))
        try write("wal", to: libraryDirectory.appendingPathComponent("Moodments.store-wal"))
        try write("shm", to: libraryDirectory.appendingPathComponent("Moodments.store-shm"))
        try write(
            "external",
            to: libraryDirectory.appendingPathComponent("Moodments.store_SUPPORT/External/blob")
        )
        try write("cloud", to: libraryDirectory.appendingPathComponent("MoodmentsCloudKit.store"))
        try write(
            "appearance", to: libraryDirectory.appendingPathComponent("Appearance/background.jpg"))
        try write("old", to: descriptor.recoveryDirectory.appendingPathComponent("old/junk.txt"))

        let manager = try RecoveryPointManager(recoveryDirectory: descriptor.recoveryDirectory)
        let metadata = try await manager.createRecoveryPoint(
            from: descriptor.payloadSource(),
            reason: .stableChanges,
            counts: RecoveryPointCounts(recordCount: 0, tagCount: 0, assetCount: 0),
            schemaVersion: 1,
            appVersion: "1.0.0",
            sourceLibraryID: descriptor.sourceLibraryID
        )

        XCTAssertEqual(metadata.sourceLibraryID, "test-local")
        var expectedFiles: [String] = []
        expectedFiles.append("Moodments.store")
        expectedFiles.append("Moodments.store-shm")
        expectedFiles.append("Moodments.store-wal")
        expectedFiles.append("Moodments.store_SUPPORT/External/blob")
        XCTAssertEqual(metadata.files.map(\.relativePath).sorted(), expectedFiles)
        XCTAssertFalse(metadata.files.contains { $0.relativePath.hasPrefix("MoodmentsCloudKit") })
        XCTAssertFalse(metadata.files.contains { $0.relativePath.hasPrefix("Appearance") })
        XCTAssertFalse(metadata.files.contains { $0.relativePath.hasPrefix("RecoveryPoints") })
    }

    func testCoordinatorCreatesRecoveryPointWithRepositoryCounts() async throws {
        let libraryDirectory = try makeSourceDirectory()
        let descriptor = LocalBackupStoreDescriptor(
            rootDirectory: libraryDirectory,
            storeFileName: "Moodments.store",
            sourceLibraryID: "test-local"
        )

        let container = try ModelContainerConfig.makeContainer(at: descriptor.storeURL)
        let tagRepository = TagRepository(modelContainer: container)
        let momentRepository = MomentRepository(modelContainer: container)
        let tagID = try await tagRepository.createTag(name: "工作")
        _ = try await momentRepository.createMoment(
            title: "本地备份",
            bodyText: "body",
            occurredAt: .now,
            mood: .happy,
            tagIDs: [tagID],
            imageDatas: [Data([0x01, 0x02, 0x03])]
        )

        let manager = try RecoveryPointManager(recoveryDirectory: descriptor.recoveryDirectory)
        let coordinator = LocalBackupCoordinator(
            descriptor: descriptor,
            recoveryPointManager: manager,
            countsRepository: RecoveryPointCountsRepository(modelContainer: container),
            appVersion: "1.0.0",
            schemaVersion: 1
        )

        let metadata = try await coordinator.createRecoveryPoint(
            reason: .stableChanges,
            createdAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(
            metadata.counts, RecoveryPointCounts(recordCount: 1, tagCount: 1, assetCount: 1))
        XCTAssertEqual(metadata.sourceLibraryID, "test-local")
        XCTAssertFalse(metadata.files.isEmpty)
        XCTAssertTrue(metadata.files.contains { $0.relativePath.hasPrefix("Moodments.store") })

        let validated = try await manager.validateRecoveryPoint(id: metadata.id)
        XCTAssertEqual(validated.status, .available)
    }

    func testLaunchRecoveryPointOnlyRunsOncePerCoordinator() async throws {
        let libraryDirectory = try makeSourceDirectory()
        let descriptor = LocalBackupStoreDescriptor(
            rootDirectory: libraryDirectory,
            storeFileName: "Moodments.store",
            sourceLibraryID: "test-local"
        )

        try write("store", to: descriptor.storeURL)
        let container = try ModelContainerConfig.makeInMemoryContainer()

        let manager = try RecoveryPointManager(recoveryDirectory: descriptor.recoveryDirectory)
        let coordinator = LocalBackupCoordinator(
            descriptor: descriptor,
            recoveryPointManager: manager,
            countsRepository: RecoveryPointCountsRepository(modelContainer: container),
            appVersion: "1.0.0",
            schemaVersion: 1
        )

        let first = try await coordinator.createLaunchRecoveryPoint(
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let second = try await coordinator.createLaunchRecoveryPoint(
            createdAt: Date(timeIntervalSince1970: 301)
        )

        XCTAssertNotNil(first)
        XCTAssertNil(second)
        let listed = try await manager.listRecoveryPoints()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.id, first?.id)
    }
}
