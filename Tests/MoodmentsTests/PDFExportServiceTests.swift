import CoreGraphics
import UIKit
import XCTest
@testable import Moodments

final class PDFExportServiceTests: XCTestCase {
    private var outputRootURL: URL!

    override func setUpWithError() throws {
        outputRootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PDFExportServiceTests-\(UUID().uuidString)",
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

    func testExportAllWritesReadablePDF() async throws {
        let fixture = try makeCanonicalFixture()
        defer { fixture.cleanup() }
        let imageData = try Self.makeJPEGData()
        try await fixture.runtime.repository.createMoment(
            title: "PDF 时刻",
            bodyText: "这条记录会进入 PDF。",
            occurredAt: Date(timeIntervalSince1970: 3_600),
            mood: .happy,
            imageDatas: [imageData]
        )
        let service = ExportService(
            snapshotProvider: CanonicalExportSnapshotStore(repository: fixture.runtime.repository),
            outputRootURL: outputRootURL,
            pdfRenderer: PDFExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)
        )

        let result = try await service.exportAll(
            format: .pdf,
            now: Date(timeIntervalSince1970: 7_200)
        )

        XCTAssertEqual(result.format, .pdf)
        XCTAssertEqual(result.fileName, "Moodments-19700101-020000.pdf")
        XCTAssertEqual(result.momentCount, 1)
        XCTAssertEqual(result.assetCount, 1)
        let data = try Data(contentsOf: result.fileURL)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let pdf = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertGreaterThanOrEqual(pdf.numberOfPages, 1)
    }

    func testExportAllRejectsEmptyPDFExport() async throws {
        let fixture = try makeCanonicalFixture()
        defer { fixture.cleanup() }
        let service = ExportService(
            snapshotProvider: CanonicalExportSnapshotStore(repository: fixture.runtime.repository),
            outputRootURL: outputRootURL,
            pdfRenderer: PDFExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)
        )

        do {
            _ = try await service.exportAll(
                format: .pdf,
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

    func testExportAllCleansPartialPackageAfterPDFRenderFailure() async throws {
        let fixture = try makeCanonicalFixture()
        defer { fixture.cleanup() }
        try await fixture.runtime.repository.createMoment(
            title: "坏图",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 3_600),
            mood: .normal,
            imageDatas: [Data([0x00, 0x01])]
        )
        let service = ExportService(
            snapshotProvider: CanonicalExportSnapshotStore(repository: fixture.runtime.repository),
            outputRootURL: outputRootURL,
            pdfRenderer: PDFExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)
        )

        await XCTAssertThrowsErrorAsync(try await service.exportAll(format: .pdf))

        let packages = try FileManager.default.contentsOfDirectory(
            at: outputRootURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(packages.isEmpty)
    }

    private static func makeJPEGData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 16))
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 4, y: 4, width: 16, height: 8))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }

    private func makeCanonicalFixture() throws -> CanonicalExportFixture {
        let assetDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PDFExportCanonicalAssets-\(UUID().uuidString)",
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

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {}
}
