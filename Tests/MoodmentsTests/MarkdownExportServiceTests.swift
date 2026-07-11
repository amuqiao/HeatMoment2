import SwiftData
import XCTest
@testable import Moodments

final class MarkdownExportServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var outputRootURL: URL!

    override func setUpWithError() throws {
        container = try ModelContainerConfig.makeInMemoryContainer()
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
        container = nil
    }

    func testExportAllWritesMarkdownAndRelativeAssets() async throws {
        let tagRepository = TagRepository(modelContainer: container)
        let momentRepository = MomentRepository(modelContainer: container)
        let tagID = try await tagRepository.createTag(name: "旅行")
        let jpegData = Data([0xFF, 0xD8, 0xFF, 0x01])
        let occurredAt = Date(timeIntervalSince1970: 3_600)

        let momentID = try await momentRepository.createMoment(
            title: "海边",
            bodyText: "今天看到了海。",
            occurredAt: occurredAt,
            mood: .happy,
            tagIDs: [tagID],
            imageDatas: [jpegData]
        )

        let service = MarkdownExportService(
            modelContainer: container,
            outputRootURL: outputRootURL,
            renderer: MarkdownExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)
        )
        let result = try await service.exportAll(now: Date(timeIntervalSince1970: 7_200))

        XCTAssertEqual(result.fileName, "Moodments-19700101-020000.md")
        XCTAssertEqual(result.momentCount, 1)
        XCTAssertEqual(result.assetCount, 1)

        let markdown = try String(contentsOf: result.markdownFileURL, encoding: .utf8)
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
        let momentRepository = MomentRepository(modelContainer: container)
        let activeID = try await momentRepository.createMoment(
            title: "保留",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 200),
            mood: .normal
        )
        let deletedID = try await momentRepository.createMoment(
            title: "不导出",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 300),
            mood: .sad
        )
        try await momentRepository.softDelete(id: deletedID)

        let service = MarkdownExportService(
            modelContainer: container,
            outputRootURL: outputRootURL,
            renderer: MarkdownExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)
        )
        let result = try await service.exportAll(now: Date(timeIntervalSince1970: 400))

        XCTAssertEqual(result.momentCount, 1)
        let markdown = try String(contentsOf: result.markdownFileURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("## 保留"))
        XCTAssertFalse(markdown.contains("不导出"))

        let page = try await momentRepository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(page.map(\.id), [activeID])
    }

    func testFileWriterCleansPartialPackageAfterWriteFailure() throws {
        let writer = MarkdownExportFileWriter(outputRootURL: outputRootURL)
        let snapshot = MarkdownExportSnapshot(
            exportedAt: Date(timeIntervalSince1970: 500),
            moments: []
        )
        let document = MarkdownExportDocument(
            markdown: "# partial",
            assets: [
                MarkdownExportRenderedAsset(relativePath: "assets/ok.jpg", data: Data([0x01])),
                MarkdownExportRenderedAsset(relativePath: "assets", data: Data([0x02]))
            ]
        )

        XCTAssertThrowsError(try writer.write(document: document, snapshot: snapshot))

        let packages = try FileManager.default.contentsOfDirectory(
            at: outputRootURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(packages.isEmpty)
    }
}
