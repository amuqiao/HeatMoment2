import XCTest
@testable import Moodments

final class RecoveryPointManagerValidationTests: RecoveryPointTestCase {
    func testValidateMarksMissingPayloadFileInvalid() async throws {
        let sourceDirectory = try makeSourceDirectory()
        let recoveryDirectory = recoveryDirectory(in: sourceDirectory)
        try write("store", to: sourceDirectory.appendingPathComponent("Moodments.store"))
        let manager = try RecoveryPointManager(recoveryDirectory: recoveryDirectory)

        let metadata = try await manager.createRecoveryPoint(
            from: makePayloadSource(
                rootDirectory: sourceDirectory,
                relativePaths: ["Moodments.store"]),
            reason: .restoreSafety,
            counts: RecoveryPointCounts(recordCount: 1, tagCount: 0, assetCount: 0),
            schemaVersion: 1,
            appVersion: "1.0.0"
        )

        let copiedStore = payloadDirectory(in: recoveryDirectory, id: metadata.id)
            .appendingPathComponent("Moodments.store")
        try FileManager.default.removeItem(at: copiedStore)

        let validated = try await manager.validateRecoveryPoint(id: metadata.id)
        XCTAssertEqual(validated.status, .invalid)

        let listed = try await manager.listRecoveryPoints()
        XCTAssertEqual(listed.first?.status, .invalid)
    }

    func testValidateMarksUnexpectedPayloadFileInvalid() async throws {
        let sourceDirectory = try makeSourceDirectory()
        let recoveryDirectory = recoveryDirectory(in: sourceDirectory)
        try write("store", to: sourceDirectory.appendingPathComponent("Moodments.store"))
        let manager = try RecoveryPointManager(recoveryDirectory: recoveryDirectory)

        let metadata = try await manager.createRecoveryPoint(
            from: makePayloadSource(
                rootDirectory: sourceDirectory,
                relativePaths: ["Moodments.store"]),
            reason: .restoreSafety,
            counts: RecoveryPointCounts(recordCount: 1, tagCount: 0, assetCount: 0),
            schemaVersion: 1,
            appVersion: "1.0.0"
        )

        try write(
            "unexpected",
            to: payloadDirectory(in: recoveryDirectory, id: metadata.id)
                .appendingPathComponent("Unexpected.txt")
        )

        let validated = try await manager.validateRecoveryPoint(id: metadata.id)
        XCTAssertEqual(validated.status, .invalid)
    }

    func testListShowsUnreadableRecoveryPointInvalid() async throws {
        let sourceDirectory = try makeSourceDirectory()
        let recoveryDirectory = recoveryDirectory(in: sourceDirectory)
        let invalidID = UUID()
        try writeInvalidMetadata(recoveryDirectory: recoveryDirectory, id: invalidID)
        let manager = try RecoveryPointManager(recoveryDirectory: recoveryDirectory)

        let listed = try await manager.listRecoveryPoints()

        XCTAssertEqual(listed.map(\.id), [invalidID])
        XCTAssertEqual(listed.first?.status, .invalid)
    }

    func testUnreadableRecoveryPointDoesNotBlockCreateAndRetention() async throws {
        let sourceDirectory = try makeSourceDirectory()
        let recoveryDirectory = recoveryDirectory(in: sourceDirectory)
        let invalidID = UUID()
        try writeInvalidMetadata(recoveryDirectory: recoveryDirectory, id: invalidID)
        try write("store", to: sourceDirectory.appendingPathComponent("Moodments.store"))
        let manager = try RecoveryPointManager(
            recoveryDirectory: recoveryDirectory,
            maxRecoveryPoints: 1
        )

        let metadata = try await manager.createRecoveryPoint(
            from: makePayloadSource(
                rootDirectory: sourceDirectory,
                relativePaths: ["Moodments.store"]),
            reason: .stableChanges,
            counts: RecoveryPointCounts(recordCount: 1, tagCount: 0, assetCount: 0),
            schemaVersion: 1,
            appVersion: "1.0.0"
        )

        let listed = try await manager.listRecoveryPoints()
        XCTAssertEqual(listed.map(\.id), [metadata.id])
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: recoveryDirectory.appendingPathComponent(invalidID.uuidString).path
            ))
    }

    private func writeInvalidMetadata(recoveryDirectory: URL, id: UUID) throws {
        try write(
            "{not-json",
            to:
                recoveryDirectory
                .appendingPathComponent(id.uuidString, isDirectory: true)
                .appendingPathComponent("metadata.json")
        )
    }
}
