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

    func testExportAllRejectsEmptyMarkdownExport() async throws {
        let fixture = try makeCanonicalFixture()
        defer { fixture.cleanup() }
        let service = ExportService(
            snapshotProvider: CanonicalExportSnapshotStore(repository: fixture.runtime.repository),
            outputRootURL: outputRootURL,
            markdownRenderer: MarkdownExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)
        )

        do {
            _ = try await service.exportAll(
                format: .markdown,
                now: Date(timeIntervalSince1970: 7_200)
            )
            XCTFail("Expected empty export to fail")
        } catch {
            XCTAssertEqual(error as? ExportError, .emptyExport)
        }

        let packages = try FileManager.default.contentsOfDirectory(
            at: outputRootURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(packages.isEmpty)
    }

    func testExportDateRangeUsesWholeDayBounds() async throws {
        let fixture = try makeCanonicalFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.runtime.repository.createMoment(
            title: "范围外较早",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 86_399),
            mood: .normal
        )
        _ = try await fixture.runtime.repository.createMoment(
            title: "范围内",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 129_600),
            mood: .happy
        )
        _ = try await fixture.runtime.repository.createMoment(
            title: "范围外较晚",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 172_800),
            mood: .sad
        )
        let service = ExportService(
            snapshotProvider: CanonicalExportSnapshotStore(
                repository: fixture.runtime.repository,
                calendar: Self.utcCalendar
            ),
            outputRootURL: outputRootURL,
            markdownRenderer: MarkdownExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)
        )

        let result = try await service.export(
            request: ExportRequest(
                scope: .dateRange(
                    start: Date(timeIntervalSince1970: 100_000),
                    end: Date(timeIntervalSince1970: 130_000)
                ),
                format: .markdown,
                includePhotos: true,
                requestedAt: Date(timeIntervalSince1970: 200_000)
            )
        )

        XCTAssertEqual(result.momentCount, 1)
        let markdown = try String(contentsOf: result.fileURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("## 范围内"))
        XCTAssertFalse(markdown.contains("范围外较早"))
        XCTAssertFalse(markdown.contains("范围外较晚"))
    }

    func testExportDateRangeIncludesWholeEndDayAndExcludesNextDay() async throws {
        let fixture = try makeCanonicalFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.runtime.repository.createMoment(
            title: "结束当天",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 172_799),
            mood: .happy
        )
        _ = try await fixture.runtime.repository.createMoment(
            title: "次日零点",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 172_800),
            mood: .normal
        )
        let service = ExportService(
            snapshotProvider: CanonicalExportSnapshotStore(
                repository: fixture.runtime.repository,
                calendar: Self.utcCalendar
            ),
            outputRootURL: outputRootURL,
            markdownRenderer: MarkdownExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)
        )

        let result = try await service.export(
            request: ExportRequest(
                scope: .dateRange(
                    start: Date(timeIntervalSince1970: 86_400),
                    end: Date(timeIntervalSince1970: 86_400)
                ),
                format: .markdown,
                includePhotos: true,
                requestedAt: Date(timeIntervalSince1970: 200_000)
            )
        )

        XCTAssertEqual(result.momentCount, 1)
        let markdown = try String(contentsOf: result.fileURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("## 结束当天"))
        XCTAssertFalse(markdown.contains("次日零点"))
    }

    func testExportDateRangeRejectsStartAfterEnd() async throws {
        let fixture = try makeCanonicalFixture()
        defer { fixture.cleanup() }
        let provider = CanonicalExportSnapshotStore(
            repository: fixture.runtime.repository,
            calendar: Self.utcCalendar
        )

        do {
            _ = try await provider.makeSnapshot(
                request: ExportRequest(
                    scope: .dateRange(
                        start: Date(timeIntervalSince1970: 172_800),
                        end: Date(timeIntervalSince1970: 86_400)
                    ),
                    format: .markdown,
                    includePhotos: true,
                    requestedAt: Date(timeIntervalSince1970: 200_000)
                )
            )
            XCTFail("Expected invalid date range to fail")
        } catch {
            XCTAssertEqual(error as? ExportError, .invalidDateRange)
        }
    }

    func testExportRequestCanExcludePhotosForMarkdownAndPDFSharedSnapshot() async throws {
        let fixture = try makeCanonicalFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.runtime.repository.createMoment(
            title: "无照片导出",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .normal,
            imageDatas: [Data([0xFF, 0xD8, 0xFF, 0x01])]
        )
        let provider = CanonicalExportSnapshotStore(repository: fixture.runtime.repository)

        let snapshot = try await provider.makeSnapshot(
            request: ExportRequest(
                scope: .all,
                format: .pdf,
                includePhotos: false,
                requestedAt: Date(timeIntervalSince1970: 200)
            )
        )

        XCTAssertEqual(snapshot.moments.count, 1)
        XCTAssertFalse(snapshot.includePhotos)
        XCTAssertTrue(snapshot.moments.first?.assets.isEmpty == true)
    }

    func testMarkdownExportWithoutPhotosWritesNoRelativeAssets() async throws {
        let fixture = try makeCanonicalFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.runtime.repository.createMoment(
            title: "只导文字",
            bodyText: "照片不进入这次导出。",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .normal,
            imageDatas: [Data([0xFF, 0xD8, 0xFF, 0x01])]
        )
        let service = ExportService(
            snapshotProvider: CanonicalExportSnapshotStore(repository: fixture.runtime.repository),
            outputRootURL: outputRootURL,
            markdownRenderer: MarkdownExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)
        )

        let result = try await service.export(
            request: ExportRequest(
                scope: .all,
                format: .markdown,
                includePhotos: false,
                requestedAt: Date(timeIntervalSince1970: 200)
            )
        )

        XCTAssertEqual(result.momentCount, 1)
        XCTAssertEqual(result.assetCount, 0)
        let markdown = try String(contentsOf: result.fileURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("## 只导文字"))
        XCTAssertFalse(markdown.contains("![照片"))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: result.packageDirectoryURL.appendingPathComponent("assets").path
            )
        )
    }

    func testExportCancellationLeavesNoPackage() async throws {
        let service = ExportService(
            snapshotProvider: CancellationExportSnapshotProvider(),
            outputRootURL: outputRootURL,
            markdownRenderer: MarkdownExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)
        )

        do {
            _ = try await service.export(
                request: ExportRequest(
                    scope: .all,
                    format: .markdown,
                    includePhotos: true,
                    requestedAt: Date(timeIntervalSince1970: 200)
                )
            )
            XCTFail("Expected cancellation to fail")
        } catch is CancellationError {
        }

        let packages = try FileManager.default.contentsOfDirectory(
            at: outputRootURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(packages.isEmpty)
    }

    func testFileWriterCleanOutputRootRemovesPreviousMoodmentsPackagesOnly() throws {
        let writer = ExportFileWriter(outputRootURL: outputRootURL)
        let stalePackage = outputRootURL.appendingPathComponent(
            "Moodments-19700101-000000-stale",
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

        let snapshot = try await provider.makeSnapshot(
            request: ExportRequest(
                scope: .all,
                format: .markdown,
                includePhotos: true,
                requestedAt: Date(timeIntervalSince1970: 300)
            )
        )

        XCTAssertEqual(snapshot.moments.map(\.id), [newerID, olderID])
        XCTAssertEqual(snapshot.moments.first?.tagNames, ["后创建", "先创建"])
        XCTAssertEqual(snapshot.moments.first?.assets.map(\.data), [Data([0x11]), Data([0x22])])
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

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private struct CanonicalExportFixture {
    let runtime: CanonicalLibraryRuntime
    let assetDirectory: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: assetDirectory)
    }
}

private struct CancellationExportSnapshotProvider: ExportSnapshotProviding {
    func makeSnapshot(request: ExportRequest) async throws -> ExportSnapshot {
        throw CancellationError()
    }
}
