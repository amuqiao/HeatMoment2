import Foundation
import UIKit

/// 图片压缩管线的错误类型。
enum ImageCompressorError: Error, Equatable {
    /// 输入 `Data` 无法被解码为图片。
    case invalidImageData
    /// `UIImage` → JPEG 编码失败。
    case jpegEncodingFailed
}

/// 原图 → JPEG 压缩管线（见 `docs/current/local-data-architecture.md` §5）：入库前统一转 JPEG
/// （HEIC 解码后重编码），长边上限约 2048px、质量约 0.8、单张目标 < 500KB。
///
/// 纯函数、`Sendable`、不持有任何状态，可在任意隔离域调用；耗时的解码/编码工作建议由调用方
/// 通过 `Task.detached` 显式切到后台执行（见 `docs/current/implementation-truth.md` §5：
/// 「耗时工作切后台」），本类型自身不做隔离域切换。
enum ImageCompressor {
    struct Configuration: Sendable, Equatable {
        var maxDimension: CGFloat
        var jpegQuality: CGFloat
        var maxByteSize: Int
        /// 为达到 `maxByteSize` 逐步降质量时的下限，避免为压体积无限降质导致画质不可接受。
        var minimumJPEGQuality: CGFloat

        init(
            maxDimension: CGFloat = 2048,
            jpegQuality: CGFloat = 0.8,
            maxByteSize: Int = 500 * 1024,
            minimumJPEGQuality: CGFloat = 0.3
        ) {
            self.maxDimension = maxDimension
            self.jpegQuality = jpegQuality
            self.maxByteSize = maxByteSize
            self.minimumJPEGQuality = minimumJPEGQuality
        }
    }

    /// - Parameters:
    ///   - data: 原始图片数据（HEIC/JPEG/PNG 等 `UIImage` 可解码的格式）。
    ///   - configuration: 压缩规格，默认对齐 docs/current/local-data-architecture.md §5。
    /// - Returns: 压缩后的 JPEG `Data`。
    /// - Throws: `ImageCompressorError.invalidImageData` 若无法解码；
    ///   `ImageCompressorError.jpegEncodingFailed` 若 JPEG 编码失败。
    static func compressToJPEG(_ data: Data, configuration: Configuration = Configuration()) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw ImageCompressorError.invalidImageData
        }
        let scaled = resized(image, maxDimension: configuration.maxDimension)

        var quality = configuration.jpegQuality
        guard var jpegData = scaled.jpegData(compressionQuality: quality) else {
            throw ImageCompressorError.jpegEncodingFailed
        }
        // 逐步降质量直到满足体积上限或达到质量下限（设下限避免死循环/画质不可接受）。
        while jpegData.count > configuration.maxByteSize, quality > configuration.minimumJPEGQuality {
            quality -= 0.1
            guard let stepped = scaled.jpegData(compressionQuality: quality) else { break }
            jpegData = stepped
        }
        return jpegData
    }

    private static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension, longestSide > 0 else { return image }
        let scale = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        // `format.scale = 1`：长边≈2048px 指的是落库图片的**真实像素**尺寸（docs/current/local-data-architecture.md §5），
        // 与渲染宿主设备的 Retina 屏幕倍率（2x/3x）无关；不显式指定的话
        // `UIGraphicsImageRenderer` 默认取当前 trait 环境的屏幕倍率，会让实际像素尺寸
        // 变成 `newSize` 的 2–3 倍，JPEG 编码/解码不携带该倍率信息，解码后尺寸会跑偏。
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
