import XCTest
import SwiftData
@testable import Moodments

/// `MomentRepository` 编辑态载入/图片重建测试（见 `docs/plans/implementation-plan.md` 阶段 3：
/// `editingPayload` 供 `.edit` 载入，`updateMoment(imageDatas:)` 非 `nil` 时级联删旧图片、
/// 按新顺序重建）。
final class MomentRepositoryEditingTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: MomentRepository!
    private var tagRepository: TagRepository!

    override func setUpWithError() throws {
        container = try ModelContainerConfig.makeInMemoryContainer()
        repository = MomentRepository(modelContainer: container)
        tagRepository = TagRepository(modelContainer: container)
    }

    override func tearDown() {
        container = nil
        repository = nil
        tagRepository = nil
    }

    func testEditingPayloadReturnsSnapshotTagNamesAndImageDatas() async throws {
        let tagID = try await tagRepository.createTag(name: "工作")
        let imageDatas: [Data] = [Data([0x01]), Data([0x02]), Data([0x03])]
        let id = try await repository.createMoment(
            title: "标题", bodyText: "正文", occurredAt: .now, mood: .happy,
            tagIDs: [tagID], imageDatas: imageDatas
        )

        let payload = try await repository.editingPayload(id: id)

        XCTAssertEqual(payload.snapshot.id, id)
        XCTAssertEqual(payload.snapshot.title, "标题")
        XCTAssertEqual(payload.snapshot.bodyText, "正文")
        XCTAssertEqual(payload.snapshot.mood, .happy)
        XCTAssertEqual(payload.snapshot.tagIDs, [tagID])
        XCTAssertEqual(payload.tagNames[tagID], "工作")
        XCTAssertEqual(payload.imageDatas, imageDatas, "图片应按 sortIndex 有序返回")
    }

    func testEditingPayloadThrowsForMissingID() async throws {
        let missingID = UUID()

        do {
            _ = try await repository.editingPayload(id: missingID)
            XCTFail("期望抛出 RepositoryError.momentNotFound，但没有抛出")
        } catch RepositoryError.momentNotFound(let notFoundID) {
            XCTAssertEqual(notFoundID, missingID)
        } catch {
            XCTFail("期望 RepositoryError.momentNotFound，实际抛出 \(error)")
        }
    }

    func testUpdateMomentReplacesImages() async throws {
        let oldDatas: [Data] = [Data([0x01]), Data([0x02])]
        let id = try await repository.createMoment(
            title: "t", bodyText: "b", occurredAt: .now, mood: .normal, imageDatas: oldDatas
        )
        let countBeforeUpdate = try await repository.imageCount(momentID: id)
        XCTAssertEqual(countBeforeUpdate, 2)

        let newDatas: [Data] = [Data([0xAA]), Data([0xBB]), Data([0xCC])]
        try await repository.updateMoment(id: id, imageDatas: newDatas)

        let payload = try await repository.editingPayload(id: id)
        XCTAssertEqual(payload.imageDatas, newDatas)
        let countAfterUpdate = try await repository.imageCount(momentID: id)
        XCTAssertEqual(countAfterUpdate, 3)

        // 只读 context 校验旧图片确实被级联删除、未残留孤儿记录。
        let verificationContext = ModelContext(container)
        let allImages = try verificationContext.fetch(FetchDescriptor<MomentImage>())
        XCTAssertEqual(allImages.count, 3, "更新图片后不应残留旧的 MomentImage 记录")
    }

    func testUpdateMomentWithNilImageDatasKeepsExistingImages() async throws {
        let datas: [Data] = [Data([0x01])]
        let id = try await repository.createMoment(
            title: "t", bodyText: "b", occurredAt: .now, mood: .normal, imageDatas: datas
        )

        try await repository.updateMoment(id: id, title: "新标题")

        let countAfterUpdate = try await repository.imageCount(momentID: id)
        XCTAssertEqual(countAfterUpdate, 1, "未传 imageDatas 不应影响既有图片")
    }
}
