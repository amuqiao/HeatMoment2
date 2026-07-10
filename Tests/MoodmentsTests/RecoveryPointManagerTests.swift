import SwiftData
import XCTest
@testable import Moodments

final class RecoveryPointManagerTests: RecoveryPointTestCase {
    func testCreateRecoveryPointCopiesPayloadAndWritesMetadata() async throws {
        let sourceDirectory = try makeSourceDirectory()
        let recoveryDirectory = recoveryDirectory(in: sourceDirectory)
        try write("store", to: sourceDirectory.appendingPathComponent("Moodments.store"))
        try write("wal", to: sourceDirectory.appendingPathComponent("Moodments.store-wal"))
        try write(
            "should not copy",
            to: sourceDirectory.appendingPathComponent("RecoveryPoints/old/junk.txt"))
        try write(
            "local preference",
            to: sourceDirectory.appendingPathComponent("Appearance/background.jpg"))

        let manager = try RecoveryPointManager(recoveryDirectory: recoveryDirectory)
        let source = makePayloadSource(
            rootDirectory: sourceDirectory,
            relativePaths: ["Moodments.store", "Moodments.store-wal"])

        let metadata = try await manager.createRecoveryPoint(
            from: source,
            reason: .stableChanges,
            counts: RecoveryPointCounts(recordCount: 2, tagCount: 1, assetCount: 0),
            schemaVersion: 1,
            appVersion: "1.0.0",
            sourceLibraryID: "library-a",
            createdAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(metadata.reason, .stableChanges)
        XCTAssertEqual(metadata.status, .available)
        XCTAssertEqual(metadata.counts.recordCount, 2)
        XCTAssertEqual(metadata.sourceLibraryID, "library-a")
        XCTAssertEqual(
            metadata.files.map(\.relativePath).sorted(),
            ["Moodments.store", "Moodments.store-wal"])

        let payloadDirectory = payloadDirectory(in: recoveryDirectory, id: metadata.id)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: payloadDirectory.appendingPathComponent("Moodments.store").path
            ))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: payloadDirectory.appendingPathComponent("RecoveryPoints/old/junk.txt").path
            ))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: payloadDirectory.appendingPathComponent("Appearance/background.jpg").path
            ))

        let validated = try await manager.validateRecoveryPoint(id: metadata.id)
        XCTAssertEqual(validated.status, .available)
    }

    func testRetentionKeepsNewestThreeRecoveryPoints() async throws {
        let sourceDirectory = try makeSourceDirectory()
        let recoveryDirectory = recoveryDirectory(in: sourceDirectory)
        let manager = try RecoveryPointManager(recoveryDirectory: recoveryDirectory)
        var created: [RecoveryPointMetadata] = []

        for index in 0..<4 {
            try write(
                "store-\(index)", to: sourceDirectory.appendingPathComponent("Moodments.store"))
            let metadata = try await manager.createRecoveryPoint(
                from: makePayloadSource(
                    rootDirectory: sourceDirectory,
                    relativePaths: ["Moodments.store"]),
                reason: .stableChanges,
                counts: RecoveryPointCounts(recordCount: index, tagCount: 0, assetCount: 0),
                schemaVersion: 1,
                appVersion: "1.0.0",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
            created.append(metadata)
        }

        let listed = try await manager.listRecoveryPoints()
        XCTAssertEqual(listed.map(\.id), created.suffix(3).reversed().map(\.id))
        XCTAssertEqual(listed.count, 3)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: recoveryDirectory.appendingPathComponent(created[0].id.uuidString).path
            ))
    }

    func testInitRejectsInvalidRetentionLimit() throws {
        XCTAssertThrowsError(
            try RecoveryPointManager(
                recoveryDirectory: tempDirectory,
                maxRecoveryPoints: 0
            )
        ) { error in
            XCTAssertEqual(error as? RecoveryPointError, .invalidMaxRecoveryPoints(0))
        }
    }

    func testCreateRecoveryPointFromSwiftDataDiskDirectory() async throws {
        let libraryDirectory = tempDirectory.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(
            at: libraryDirectory,
            withIntermediateDirectories: true
        )
        let storeURL = libraryDirectory.appendingPathComponent("Moodments.store")

        do {
            let container = try ModelContainerConfig.makeContainer(at: storeURL)
            let repository = MomentRepository(modelContainer: container)
            _ = try await repository.createMoment(
                title: "disk",
                bodyText: "body",
                occurredAt: .now,
                mood: .happy,
                imageDatas: [Data([0x01, 0x02, 0x03])]
            )
        }

        let manager = try RecoveryPointManager(
            recoveryDirectory: recoveryDirectory(in: libraryDirectory)
        )
        let metadata = try await manager.createRecoveryPoint(
            from: RecoveryPointPayloadSource(
                rootDirectory: libraryDirectory,
                includedURLs: try swiftDataStorePayloadURLs(in: libraryDirectory)
            ),
            reason: .schemaMigration,
            counts: RecoveryPointCounts(recordCount: 1, tagCount: 0, assetCount: 1),
            schemaVersion: 1,
            appVersion: "1.0.0"
        )

        XCTAssertFalse(metadata.files.isEmpty)
        XCTAssertTrue(metadata.files.contains { $0.relativePath.hasPrefix("Moodments.store") })
        XCTAssertFalse(metadata.files.contains { $0.relativePath.hasPrefix("RecoveryPoints") })
        let validated = try await manager.validateRecoveryPoint(id: metadata.id)
        XCTAssertEqual(validated.status, .available)
    }
}
