import CoreGraphics
import SwiftData
import UIKit
import XCTest
@testable import Moodments

final class PDFExportServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var outputRootURL: URL!

    override func setUpWithError() throws {
        container = try ModelContainerConfig.makeInMemoryContainer()
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
        container = nil
    }

    func testExportAllWritesReadablePDF() async throws {
        let momentRepository = MomentRepository(modelContainer: container)
        let imageData = try Self.makeJPEGData()
        try await momentRepository.createMoment(
            title: "PDF 时刻",
            bodyText: "这条记录会进入 PDF。",
            occurredAt: Date(timeIntervalSince1970: 3_600),
            mood: .happy,
            imageDatas: [imageData]
        )
        let service = ExportService(
            modelContainer: container,
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

    func testExportAllCleansPartialPackageAfterPDFRenderFailure() async throws {
        let momentRepository = MomentRepository(modelContainer: container)
        try await momentRepository.createMoment(
            title: "坏图",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 3_600),
            mood: .normal,
            imageDatas: [Data([0x00, 0x01])]
        )
        let service = ExportService(
            modelContainer: container,
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
