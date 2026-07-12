import XCTest
import UIKit
@testable import Moodments

/// `ImageCompressor` 压缩管线测试（见 `docs/current/local-data-architecture.md` §5：
/// 长边≈2048、质量≈0.8、单张<500KB）。
final class ImageCompressorTests: XCTestCase {
    func testCompressToJPEGProducesDecodableJPEGWithinConfiguredBounds() throws {
        let original = Self.makeSolidImage(size: CGSize(width: 4000, height: 3000))
        guard let originalData = original.pngData() else {
            return XCTFail("测试夹具生成失败")
        }

        let configuration = ImageCompressor.Configuration(maxDimension: 1024, jpegQuality: 0.8, maxByteSize: 200 * 1024)
        let compressed = try ImageCompressor.compressToJPEG(originalData, configuration: configuration)

        XCTAssertLessThanOrEqual(compressed.count, configuration.maxByteSize)

        let decoded = try XCTUnwrap(UIImage(data: compressed))
        XCTAssertLessThanOrEqual(max(decoded.size.width, decoded.size.height), configuration.maxDimension + 1)
    }

    func testCompressToJPEGThrowsForInvalidData() {
        XCTAssertThrowsError(try ImageCompressor.compressToJPEG(Data([0x00, 0x01, 0x02]))) { error in
            XCTAssertEqual(error as? ImageCompressorError, .invalidImageData)
        }
    }

    private static func makeSolidImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
