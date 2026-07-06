import Foundation

/// 缩略图缓存（见 `docs/design/07-data-persistence.md` §5）：内存 + `Caches/thumbnails/`
/// 两级，命中则用、未命中则从原图现场生成并回写；缩略图**不参与 CloudKit 同步**，可随时基于
/// 原图重新生成。`Caches/` 目录本身可被系统随时回收，故磁盘读写失败按「缓存未命中/写入放弃」
/// 处理，不视为需要上抛的业务错误（见下方各方法内注释）。用 `actor` 封装保证并发安全
/// （见 `docs/design/08-architecture.md` §5：共享可变状态用 `actor` 封装）。
actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private var memoryCache: [UUID: Data] = [:]
    private let cacheDirectory: URL

    init(cacheDirectory: URL = ThumbnailCache.defaultCacheDirectory()) {
        self.cacheDirectory = cacheDirectory
    }

    static func defaultCacheDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("thumbnails", isDirectory: true)
    }

    /// 取指定图片的缩略图：命中内存/磁盘缓存则直接返回；未命中则调用 `originalData` 现场
    /// 生成并回写两级缓存（见 07 §5「命中缓存则用、未命中则从原图现场生成并回写」）。
    /// - Parameters:
    ///   - imageID: 对应 `MomentImage.id`。
    ///   - originalData: 生成缩略图所需的原图 `Data` 来源（由调用方按需从仓库读取，避免
    ///     缓存命中时的无谓 IO）。
    func thumbnail(
        for imageID: UUID,
        maxDimension: CGFloat = 240,
        originalData: @Sendable () throws -> Data
    ) throws -> Data {
        if let cached = memoryCache[imageID] {
            return cached
        }
        let fileURL = cacheDirectory.appendingPathComponent("\(imageID.uuidString).jpg")
        // 磁盘缓存「未命中」（文件不存在）与「读取出错」在这里的补救动作完全相同——都是从
        // 原图现场重新生成，因此统一按未命中处理，不是把一个需要上抛的业务错误吞掉。
        if let cachedOnDisk = try? Data(contentsOf: fileURL) {
            memoryCache[imageID] = cachedOnDisk
            return cachedOnDisk
        }
        let original = try originalData()
        let thumbnailData = try ImageCompressor.compressToJPEG(
            original,
            configuration: .init(maxDimension: maxDimension, jpegQuality: 0.7, maxByteSize: 150 * 1024)
        )
        memoryCache[imageID] = thumbnailData
        persistBestEffort(thumbnailData, to: fileURL)
        return thumbnailData
    }

    /// Moment 彻底删除时同步清理其缩略图缓存（内存 + 磁盘，见 07 §5）。
    func removeThumbnail(for imageID: UUID) {
        memoryCache.removeValue(forKey: imageID)
        let fileURL = cacheDirectory.appendingPathComponent("\(imageID.uuidString).jpg")
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 磁盘写入是缓存优化的「尽力而为」：`Caches/` 目录本就可被系统随时回收、缩略图可随时从
    /// 原图重新生成，写入失败不影响本次调用已经算出的正确结果，因此有意不上抛（见类型头部）。
    private func persistBestEffort(_ data: Data, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            // 有意不上抛：见本方法与类型头部注释（Caches 可回收、缩略图可重建）。
        }
    }
}
