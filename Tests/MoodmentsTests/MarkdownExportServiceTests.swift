import XCTest
@testable import Moodments

final class MarkdownExportServiceTests: XCTestCase {
    private var outputRootURL: URL!

    override func setUpWithError() throws {
        outputRootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MarkdownExportServiceTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputRootURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let outputRootURL, FileManager.default.fileExists(atPath: outputRootURL.path) {
            try FileManager.default.removeItem(at: outputRootURL)
        }
        outputRootURL = nil
    }

    func testExportAllWritesMarkdownAndRelativeAssets() async throws {
        let fixture = try makeCanonicalFixture()
        defer { fixture.cleanup() }
        let tag = try await fixture.runtime.repository.createOrReuseTag(name: "旅行")
        let jpegData = Data([0xFF, 0xD8, 0xFF, 0x01])
        let occurredAt = Date(timeIntervalSince1970: 3_600)

        let momentID = try await fixture.runtime.repository.createMoment(
            title: "海边",
            bodyText: "今天看到了海。",
            occurredAt: occurredAt,
            mood: .happy,
            tagIDs: [tag.id],
            imageDatas: [jpegData]
        )

        let service = ExportService(
            snapshotProvider: CanonicalExportSnapshotStore(repository: fixture.runtime.repository),
            outputRootURL: outputRootURL,
            markdownRenderer: MarkdownExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)
        )
        let result = try await service.exportAll(
            format: .markdown,
            now: Date(timeIntervalSince1970: 7_200)
        )

        XCTAssertEqual(result.fileName, "Moodments-19700101-020000.md")
        XCTAssertEqual(result.format, .markdown)
        XCTAssertEqual(result.momentCount, 1)
        XCTAssertEqual(result.assetCount, 1)

        let markdown = try String(contentsOf: result.fileURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("# 时刻导出"))
        XCTAssertTrue(markdown.contains("- 导出时间：1970-01-01 02:00"))
        XCTAssertTrue(markdown.contains("## 海边"))
        XCTAssertTrue(markdown.contains("- 发生时间：1970-01-01 01:00"))
        XCTAssertTrue(markdown.contains("- 心情：😄"))
        XCTAssertTrue(markdown.contains("- 标签：#旅行"))
        XCTAssertTrue(markdown.contains("今天看到了海。"))

        let expectedAssetPath = "assets/moment-\(momentID.uuidString.lowercased())-image-1.jpg"
        XCTAssertTrue(markdown.contains("![照片 1](\(expectedAssetPath))"))
        let assetURL = result.packageDirectoryURL.appendingPathComponent(expectedAssetPath)
        XCTAssertEqual(try Data(contentsOf: assetURL), jpegData)
    }

    func testExportAllExcludesSoftDeletedMoments() async throws {
        let fixture = try makeCanonicalFixture()
        defer { fixture.cleanup() }
        let activeID = try await fixture.runtime.repository.createMoment(
            title: "保留",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 200),
            mood: .normal
        )
        let deletedID = try await fixture.runtime.repository.createMoment(
            title: "不导出",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 300),
            mood: .sad
        )
        try await fixture.runtime.repository.softDeleteMoment(id: deletedID)

        let service = ExportService(
            snapshotProvider: CanonicalExportSnapshotStore(repository: fixture.runtime.repository),
            outputRootURL: outputRootURL,
            markdownRenderer: MarkdownExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)
        )
        let result = try await service.exportAll(
            format: .markdown,
            now: Date(timeIntervalSince1970: 400)
        )

        XCTAssertEqual(result.momentCount, 1)
        let markdown = try String(contentsOf: result.fileURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("## 保留"))
        XCTAssertFalse(markdown.contains("不导出"))

        let page = try await fixture.runtime.repository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(page.map(\.id), [activeID])
    }

    func testExportAllWritesEmptyMarkdownPackage() async throws {
        let fixture = try makeCanonicalFixture()
        defer { fixture.cleanup() }
        let service = ExportService(
            snapshotProvider: CanonicalExportSnapshotStore(repository: fixture.runtime.repository),
            outputRootURL: outputRootURL,
            markdownRenderer: MarkdownExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)
        )

        let result = try await service.exportAll(
            format: .markdown,
            now: Date(timeIntervalSince1970: 7_200)
        )

        XCTAssertEqual(result.momentCount, 0)
        XCTAssertEqual(result.assetCount, 0)
        XCTAssertEqual(result.fileName, "Moodments-19700101-020000.md")
        let markdown = try String(contentsOf: result.fileURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("- 时刻数量：0"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.packageDirectoryURL.path))
    }

    func testCanonicalSnapshotUsesTimelineTagAndImageOrder() async throws {
        let fixture = try makeCanonicalFixture()
        defer { fixture.cleanup() }
        let firstTag = try await fixture.runtime.repository.createOrReuseTag(name: "先创建")
        let secondTag = try await fixture.runtime.repository.createOrReuseTag(name: "后创建")
        let olderID = try await fixture.runtime.repository.createMoment(
            title: "较早",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .normal
        )
        let newerID = try await fixture.runtime.repository.createMoment(
            title: "较晚",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 200),
            mood: .happy,
            tagIDs: [secondTag.id, firstTag.id],
            imageDatas: [Data([0x11]), Data([0x22])]
        )
        let provider = CanonicalExportSnapshotStore(repository: fixture.runtime.repository)

        let snapshot = try await provider.makeSnapshot(exportedAt: Date(timeIntervalSince1970: 300))

        XCTAssertEqual(snapshot.moments.map(\.id), [newerID, olderID])
        XCTAssertEqual(snapshot.moments.first?.tagNames, ["后创建", "先创建"])
        XCTAssertEqual(snapshot.moments.first?.assets.map(\.data), [Data([0x11]), Data([0x22])])
    }

    func testFileWriterCleansPartialPackageAfterWriteFailure() throws {
        let writer = ExportFileWriter(outputRootURL: outputRootURL)
        let snapshot = ExportSnapshot(
            exportedAt: Date(timeIntervalSince1970: 500),
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

    private func makeCanonicalFixture() throws -> CanonicalExportFixture {
        let assetDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MarkdownExportCanonicalAssets-\(UUID().uuidString)",
            isDirectory: true
        )
        return CanonicalExportFixture(
            runtime: try CanonicalLibraryRuntime.makeInMemoryForTests(
                assetDirectoryURL: assetDirectory
            ),
            assetDirectory: assetDirectory
        )
    }
}

private struct CanonicalExportFixture {
    let runtime: CanonicalLibraryRuntime
    let assetDirectory: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: assetDirectory)
    }
}
