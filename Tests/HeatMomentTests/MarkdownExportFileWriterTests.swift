import XCTest
@testable import HeatMoment

final class MarkdownExportFileWriterTests: MarkdownExportServiceTestCase {
    func testFileWriterCleanOutputRootRemovesPreviousHeatMomentPackagesOnly() throws {
        let writer = ExportFileWriter(outputRootURL: outputRootURL)
        let stalePackage = outputRootURL.appendingPathComponent(
            "HeatMoment-19700101-000000-stale",
            isDirectory: true
        )
        let userFile = outputRootURL.appendingPathComponent("keep.txt")
        try FileManager.default.createDirectory(
            at: stalePackage,
            withIntermediateDirectories: true
        )
        try Data("keep".utf8).write(to: userFile)

        try writer.cleanOutputRoot()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stalePackage.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: userFile.path))
    }

    func testFileWriterCleansPartialPackageAfterWriteFailure() throws {
        let writer = ExportFileWriter(outputRootURL: outputRootURL)
        let snapshot = ExportSnapshot(
            exportedAt: Date(timeIntervalSince1970: 500),
            scope: .all,
            includePhotos: true,
            moments: []
        )
        let document = MarkdownExportDocument(
            markdown: "# partial",
            // swiftlint:disable trailing_comma
            assets: [
                MarkdownExportRenderedAsset(relativePath: "assets/ok.jpg", data: Data([0x01])),
                MarkdownExportRenderedAsset(relativePath: "assets", data: Data([0x02])),
            ]
            // swiftlint:enable trailing_comma
        )

        XCTAssertThrowsError(try writer.writeMarkdown(document: document, snapshot: snapshot))

        let packages = try FileManager.default.contentsOfDirectory(
            at: outputRootURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(packages.isEmpty)
    }
}
