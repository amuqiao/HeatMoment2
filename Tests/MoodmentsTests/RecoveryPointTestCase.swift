import XCTest
@testable import Moodments

class RecoveryPointTestCase: XCTestCase {
    var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MoodmentsRecoveryPointTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    func makeSourceDirectory() throws -> URL {
        let sourceDirectory = tempDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        return sourceDirectory
    }

    func recoveryDirectory(in sourceDirectory: URL) -> URL {
        sourceDirectory.appendingPathComponent("RecoveryPoints", isDirectory: true)
    }

    func payloadDirectory(in recoveryDirectory: URL, id: UUID) -> URL {
        recoveryDirectory
            .appendingPathComponent(id.uuidString, isDirectory: true)
            .appendingPathComponent("payload", isDirectory: true)
    }

    func makePayloadSource(
        rootDirectory: URL,
        relativePaths: [String]
    ) -> RecoveryPointPayloadSource {
        RecoveryPointPayloadSource(
            rootDirectory: rootDirectory,
            includedURLs: relativePaths.map { rootDirectory.appendingPathComponent($0) }
        )
    }

    func swiftDataStorePayloadURLs(in libraryDirectory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: libraryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.lastPathComponent.hasPrefix("Moodments.store") }
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
    }
}
