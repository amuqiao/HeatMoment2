import XCTest
import SwiftData
@testable import Moodments

/// `MomentRepository` 取图方法验收（见阶段 4 计划：`orderedImageData`/`imageData` 供
/// `ImageViewerView`/`ThumbnailStripView` 使用，见 `docs/design/07-data-persistence.md` §5）。
final class MomentImageFetchTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: MomentRepository!

    override func setUpWithError() throws {
        container = try ModelContainerConfig.makeInMemoryContainer()
        repository = MomentRepository(modelContainer: container)
    }

    override func tearDown() {
        container = nil
        repository = nil
    }

    func testOrderedImageDataIsSortedBySortIndex() async throws {
        let imageDatas: [Data] = [Data([0x01]), Data([0x02]), Data([0x03])]
        let momentID = try await repository.createMoment(
            title: "t", bodyText: "", occurredAt: .now, mood: .happy, imageDatas: imageDatas
        )

        let ordered = try await repository.orderedImageData(momentID: momentID)

        XCTAssertEqual(ordered.map(\.data), imageDatas, "应按 sortIndex（追加顺序）有序返回")
    }

    func testOrderedImageDataThrowsForMissingMoment() async throws {
        let missingID = UUID()

        do {
            _ = try await repository.orderedImageData(momentID: missingID)
            XCTFail("期望抛出 RepositoryError.momentNotFound，但没有抛出")
        } catch RepositoryError.momentNotFound(let notFoundID) {
            XCTAssertEqual(notFoundID, missingID)
        } catch {
            XCTFail("期望 RepositoryError.momentNotFound，实际抛出 \(error)")
        }
    }

    func testImageDataReturnsMatchingBytesForKnownID() async throws {
        let imageDatas: [Data] = [Data([0xAA, 0xBB])]
        let momentID = try await repository.createMoment(
            title: "t", bodyText: "", occurredAt: .now, mood: .normal, imageDatas: imageDatas
        )
        let ordered = try await repository.orderedImageData(momentID: momentID)
        let imageID = try XCTUnwrap(ordered.first?.id)

        let data = try await repository.imageData(imageID: imageID)

        XCTAssertEqual(data, Data([0xAA, 0xBB]))
    }

    /// 不存在的 imageID 必须快速失败，不允许静默返回空/默认值
    /// （见 `CLAUDE.md`「不擅自添加兜底策略」，与本仓库其余按 id 操作方法一致）。
    func testImageDataThrowsForMissingID() async throws {
        let missingImageID = UUID()

        do {
            _ = try await repository.imageData(imageID: missingImageID)
            XCTFail("期望抛出 RepositoryError.momentImageNotFound，但没有抛出")
        } catch RepositoryError.momentImageNotFound(let notFoundID) {
            XCTAssertEqual(notFoundID, missingImageID)
        } catch {
            XCTFail("期望 RepositoryError.momentImageNotFound，实际抛出 \(error)")
        }
    }
}
