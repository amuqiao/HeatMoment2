import CoreGraphics
import UIKit
import XCTest
@testable import HeatMoment

final class PDFExportRendererTests: XCTestCase {
    func testRendererCreatesReadablePDFWithLongTextAndImage() throws {
        let imageData = try Self.makeJPEGData()
        let snapshot = ExportSnapshot(
            exportedAt: Date(timeIntervalSince1970: 0),
            scope: .dateRange(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 86_400)
            ),
            includePhotos: true,
            moments: [
                ExportMoment(
                    id: UUID(),
                    title: "很长的时刻",
                    bodyText: Array(repeating: "这是一段用于分页的正文。", count: 360).joined(),
                    occurredAt: Date(timeIntervalSince1970: 60),
                    mood: .happy,
                    tagNames: ["旅行", "家人"],
                    assets: [ExportAsset(id: UUID(), data: imageData)]
                )
            ]
        )
        let renderer = PDFExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)

        let document = try renderer.render(snapshot: snapshot)

        XCTAssertTrue(document.data.starts(with: Data("%PDF".utf8)))
        let provider = try XCTUnwrap(CGDataProvider(data: document.data as CFData))
        let pdf = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertGreaterThan(pdf.numberOfPages, 1)
        XCTAssertNotNil(document.data.range(of: Data("/Image".utf8)))
    }

    func testRendererFailsForInvalidImageData() {
        let assetID = UUID()
        let momentID = UUID()
        let snapshot = ExportSnapshot(
            exportedAt: Date(timeIntervalSince1970: 0),
            scope: .dateRange(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 86_400)
            ),
            includePhotos: true,
            moments: [
                ExportMoment(
                    id: momentID,
                    title: "坏图",
                    bodyText: "",
                    occurredAt: Date(timeIntervalSince1970: 60),
                    mood: .normal,
                    tagNames: [],
                    assets: [ExportAsset(id: assetID, data: Data([0x00, 0x01]))]
                )
            ]
        )
        let renderer = PDFExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)

        XCTAssertThrowsError(try renderer.render(snapshot: snapshot)) { error in
            XCTAssertEqual(
                error as? ExportError,
                .pdfImageDecodingFailed(momentID: momentID, assetID: assetID)
            )
        }
    }

    private static func makeJPEGData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 16))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
            UIColor.systemYellow.setFill()
            context.fill(CGRect(x: 6, y: 4, width: 12, height: 8))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }
}
