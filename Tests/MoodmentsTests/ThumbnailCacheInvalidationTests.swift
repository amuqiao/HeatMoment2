import XCTest
import UIKit
@testable import Moodments

/// 缩略图缓存失效验收（见 `docs/design/07-data-persistence.md` §5、阶段 4 计划 §8 延后项）：
/// `removeThumbnail` 后下一次取图必须重新触发 provider（重生成，不能继续用陈旧缓存）；
/// `MomentEditorModel.save()` 的 `.edit` 分支保存成功后必须失效 `originalImageIDs`
/// （旧 canonical asset link 被重建为全新 id，避免孤儿缓存永久占用）。
final class ThumbnailCacheInvalidationTests: XCTestCase {
    private var tempDirectory: URL!
    private var cache: ThumbnailCache!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThumbnailCacheTests-\(UUID().uuidString)", isDirectory: true)
        cache = ThumbnailCache(cacheDirectory: tempDirectory)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        cache = nil
    }

    func testRemoveThumbnailForcesProviderToRegenerateOnNextFetch() async throws {
        let imageID = UUID()
        let callCounter = CallCounter()

        _ = try await cache.thumbnail(for: imageID) {
            await callCounter.increment()
            return Self.makeSyntheticJPEGData()
        }
        let countAfterFirstFetch = await callCounter.value
        XCTAssertEqual(countAfterFirstFetch, 1)

        // 缓存命中：provider 不应再被调用。
        _ = try await cache.thumbnail(for: imageID) {
            await callCounter.increment()
            return Self.makeSyntheticJPEGData()
        }
        let countAfterCacheHit = await callCounter.value
        XCTAssertEqual(countAfterCacheHit, 1, "缓存命中不应再调用 provider")

        await cache.removeThumbnail(for: imageID)
        let hasCachedAfterRemoval = await cache.hasMemoryCachedThumbnail(for: imageID)
        XCTAssertFalse(hasCachedAfterRemoval)

        // 失效后再次取图：provider 应被重新调用（重生成）。
        _ = try await cache.thumbnail(for: imageID) {
            await callCounter.increment()
            return Self.makeSyntheticJPEGData()
        }
        let countAfterInvalidate = await callCounter.value
        XCTAssertEqual(countAfterInvalidate, 2, "removeThumbnail 后应重新触发 provider 生成")
    }

    /// 编辑保存（`.edit`）成功后，`MomentEditorModel` 应失效原有 `originalImageIDs` 对应的
    /// 共享 `ThumbnailCache.shared` 缓存键（`updateMoment(imageDatas:)` 级联删除旧
    /// canonical asset link 并重建全新 id，旧键此后必然是孤儿键，见 `MomentEditorModel` 注释）。
    @MainActor
    func testEditSaveInvalidatesOriginalImageIDsThumbnailCache() async throws {
        let canonicalService = try CanonicalLibraryService(
            runtime: .makeInMemoryForTests(
                assetDirectoryURL: tempDirectory.appendingPathComponent(
                    "CanonicalAssets",
                    isDirectory: true
                )
            )
        )
        let momentID = try await canonicalService.repository.createMoment(
            title: "t", bodyText: "", occurredAt: .now, mood: .normal,
            imageDatas: [Self.makeSyntheticJPEGData()]
        )
        let originalImages = try await canonicalService.orderedImageData(momentID: momentID)
        let originalImageID = try XCTUnwrap(originalImages.first?.id)

        // 预热共享缓存（`MomentEditorModel.save()` 实际失效的是这个单例）。
        _ = try await ThumbnailCache.shared.thumbnail(for: originalImageID) {
            try await canonicalService.imageData(imageID: originalImageID)
        }
        let hasCachedBeforeSave = await ThumbnailCache.shared.hasMemoryCachedThumbnail(
            for: originalImageID)
        XCTAssertTrue(hasCachedBeforeSave)

        let model = MomentEditorModel(
            mode: .edit(momentID),
            canonicalService: canonicalService,
            subscriptionService: SubscriptionService()
        )
        let mutationService = LocalLibraryMutationService(
            canonicalService: canonicalService,
            syncStatusService: SyncStatusService(
                cloudKitEnabled: false,
                reachabilityChecker: ImmediateReachabilityChecker()
            ),
            errorPresenter: ErrorPresenter()
        )
        try await model.load()
        try await model.save(using: mutationService)

        let hasCachedAfterSave = await ThumbnailCache.shared.hasMemoryCachedThumbnail(
            for: originalImageID)
        XCTAssertFalse(hasCachedAfterSave, "编辑保存后旧 imageID 的缩略图缓存应已被失效")
    }

    private static func makeSyntheticJPEGData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        // swiftlint:disable:next force_unwrapping
        return image.jpegData(compressionQuality: 0.9)!
    }
}

private actor CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private struct ImmediateReachabilityChecker: NetworkReachabilityChecking {
    func isReachable() async -> Bool { true }
}
