import XCTest
import SwiftData
@testable import Moodments

/// `MomentRepository` 的照片计数/级联删除、字段更新、分页查询测试。
final class MomentRepositoryTests: XCTestCase {
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

    // MARK: - 照片

    func testCreateMomentWithThreePhotosReportsImageCountThree() async throws {
        let imageDatas: [Data] = [Data([0x01]), Data([0x02]), Data([0x03])]
        let id = try await repository.createMoment(
            title: "with photos",
            bodyText: "",
            occurredAt: .now,
            mood: .happy,
            imageDatas: imageDatas
        )

        let count = try await repository.imageCount(momentID: id)
        XCTAssertEqual(count, 3)

        let page = try await repository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(page.first?.imageIDs.count, 3)
    }

    func testPurgeCascadesRemovalOfImages() async throws {
        let imageDatas: [Data] = [Data([0x01]), Data([0x02]), Data([0x03])]
        let id = try await repository.createMoment(
            title: "with photos",
            bodyText: "",
            occurredAt: .now,
            mood: .happy,
            imageDatas: imageDatas
        )

        try await repository.purge(id: id)

        // 彻底删除的级联效果无法通过 Repository 的公开接口直接查询 MomentImage，
        // 借助一个只读的 ModelContext 验证底层存储确实随 Moment 一并物理移除（.cascade）。
        let verificationContext = ModelContext(container)
        let remainingImages = try verificationContext.fetch(FetchDescriptor<MomentImage>())
        XCTAssertTrue(remainingImages.isEmpty, "彻底删除应级联移除其 MomentImage（deleteRule: .cascade）")
    }

    // MARK: - 更新

    func testUpdateMomentTransitionsFieldsAndReattachesTags() async throws {
        let tagRepository = TagRepository(modelContainer: container)
        let oldTagID = try await tagRepository.createTag(name: "旧标签")
        let newTagID = try await tagRepository.createTag(name: "新标签")

        let id = try await repository.createMoment(
            title: "旧标题",
            bodyText: "旧正文",
            occurredAt: .now,
            mood: .sad,
            tagIDs: [oldTagID]
        )

        let newOccurredAt = Date(timeIntervalSince1970: 0)
        try await repository.updateMoment(
            id: id,
            title: "新标题",
            bodyText: "新正文",
            occurredAt: newOccurredAt,
            mood: .happy,
            tagIDs: [newTagID]
        )

        let page = try await repository.fetchPage(offset: 0, limit: 10)
        let updated = try XCTUnwrap(page.first { $0.id == id })
        XCTAssertEqual(updated.title, "新标题")
        XCTAssertEqual(updated.bodyText, "新正文")
        XCTAssertEqual(updated.occurredAt, newOccurredAt)
        XCTAssertEqual(updated.mood, .happy)
        XCTAssertEqual(updated.tagIDs, [newTagID])
        XCTAssertGreaterThanOrEqual(updated.updatedAt, updated.createdAt)
    }

    // MARK: - 分页

    func testFetchPageOrdersByOccurredAtDescendingWithOffsetAndLimit() async throws {
        let now = Date.now
        // 依次创建三条，occurredAt 依次更早：newest > middle > oldest。
        let oldestID = try await repository.createMoment(
            title: "oldest", bodyText: "", occurredAt: now.addingTimeInterval(-2000), mood: .normal
        )
        let middleID = try await repository.createMoment(
            title: "middle", bodyText: "", occurredAt: now.addingTimeInterval(-1000), mood: .normal
        )
        let newestID = try await repository.createMoment(
            title: "newest", bodyText: "", occurredAt: now, mood: .normal
        )

        let fullPage = try await repository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(fullPage.map(\.id), [newestID, middleID, oldestID])

        let firstPage = try await repository.fetchPage(offset: 0, limit: 2)
        XCTAssertEqual(firstPage.map(\.id), [newestID, middleID])

        let secondPage = try await repository.fetchPage(offset: 2, limit: 2)
        XCTAssertEqual(secondPage.map(\.id), [oldestID])
    }
}
