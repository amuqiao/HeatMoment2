import XCTest
@testable import HeatMoment

final class MarkdownExportTransactionTests: MarkdownExportServiceTestCase {
    func testFinishingShareTransactionCleansTemporaryPackage() async throws {
        let fixture = try makeCanonicalFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.runtime.repository.createMoment(
            title: "完成分享",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .normal
        )
        let service = ExportService(
            snapshotProvider: CanonicalExportSnapshotStore(repository: fixture.runtime.repository),
            outputRootURL: outputRootURL,
            markdownRenderer: MarkdownExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)
        )

        let transaction = try await service.prepareShareTransaction(
            request: ExportRequest(
                scope: Self.fixtureDateRangeScope,
                format: .markdown,
                includePhotos: true,
                requestedAt: Date(timeIntervalSince1970: 200)
            )
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: transaction.fileURL.path))
        try service.finishShareTransaction(transaction)
        let packages = try FileManager.default.contentsOfDirectory(
            at: outputRootURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(packages.isEmpty)
    }

    func testShareFailureKeepsPreparedTransactionForRetry() async throws {
        let fixture = try makeCanonicalFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.runtime.repository.createMoment(
            title: "分享失败重试",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .normal
        )
        let service = ExportService(
            snapshotProvider: CanonicalExportSnapshotStore(repository: fixture.runtime.repository),
            outputRootURL: outputRootURL,
            markdownRenderer: MarkdownExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)
        )

        let transaction = try await service.prepareShareTransaction(
            request: ExportRequest(
                scope: Self.fixtureDateRangeScope,
                format: .markdown,
                includePhotos: true,
                requestedAt: Date(timeIntervalSince1970: 200)
            )
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: transaction.fileURL.path))
        let packages = try FileManager.default.contentsOfDirectory(
            at: outputRootURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(packages, [transaction.packageDirectoryURL])
        try service.finishShareTransaction(transaction)
    }
}
