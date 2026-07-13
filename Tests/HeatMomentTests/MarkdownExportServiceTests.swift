import XCTest
@testable import HeatMoment

final class MarkdownExportServiceTests: MarkdownExportServiceTestCase {
    func testDateRangeExportWritesMarkdownAndRelativeAssets() async throws {
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
        let result = try await service.prepareShareTransaction(
            request: ExportRequest(
                scope: Self.fixtureDateRangeScope,
                format: .markdown,
                includePhotos: true,
                requestedAt: Date(timeIntervalSince1970: 7_200)
            )
        )

        XCTAssertEqual(result.format, .markdown)
        XCTAssertEqual(result.fileURL.lastPathComponent, "HeatMoment-19700101-020000.md")

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

    func testDateRangeExportExcludesSoftDeletedMoments() async throws {
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
        let result = try await service.prepareShareTransaction(
            request: ExportRequest(
                scope: Self.fixtureDateRangeScope,
                format: .markdown,
                includePhotos: true,
                requestedAt: Date(timeIntervalSince1970: 400)
            )
        )

        let markdown = try String(contentsOf: result.fileURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("## 保留"))
        XCTAssertFalse(markdown.contains("不导出"))

        let page = try await fixture.runtime.repository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(page.map(\.id), [activeID])
    }

    func testDateRangeExportRejectsEmptyMarkdownExport() async throws {
        let fixture = try makeCanonicalFixture()
        defer { fixture.cleanup() }
        let service = ExportService(
            snapshotProvider: CanonicalExportSnapshotStore(repository: fixture.runtime.repository),
            outputRootURL: outputRootURL,
            markdownRenderer: MarkdownExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)
        )

        do {
            _ = try await service.prepareShareTransaction(
                request: ExportRequest(
                    scope: Self.fixtureDateRangeScope,
                    format: .markdown,
                    includePhotos: true,
                    requestedAt: Date(timeIntervalSince1970: 7_200)
                )
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

        let result = try await service.prepareShareTransaction(
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

        let result = try await service.prepareShareTransaction(
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
                scope: Self.fixtureDateRangeScope,
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

        let result = try await service.prepareShareTransaction(
            request: ExportRequest(
                scope: Self.fixtureDateRangeScope,
                format: .markdown,
                includePhotos: false,
                requestedAt: Date(timeIntervalSince1970: 200)
            )
        )

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
            _ = try await service.prepareShareTransaction(
                request: ExportRequest(
                    scope: Self.fixtureDateRangeScope,
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
                scope: Self.fixtureDateRangeScope,
                format: .markdown,
                includePhotos: true,
                requestedAt: Date(timeIntervalSince1970: 300)
            )
        )

        XCTAssertEqual(snapshot.moments.map(\.id), [newerID, olderID])
        XCTAssertEqual(snapshot.moments.first?.tagNames, ["后创建", "先创建"])
        XCTAssertEqual(snapshot.moments.first?.assets.map(\.data), [Data([0x11]), Data([0x22])])
    }

}

private struct CancellationExportSnapshotProvider: ExportSnapshotProviding {
    func makeSnapshot(request: ExportRequest) async throws -> ExportSnapshot {
        throw CancellationError()
    }
}
