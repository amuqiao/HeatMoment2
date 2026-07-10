import XCTest
import SwiftData
@testable import Moodments

/// `TagRepository` 测试：应用层查重、增删、额度计数（唯一性由应用层保证，见
/// `docs/design/07-data-persistence.md` §2、§4）。
final class TagRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: TagRepository!

    override func setUpWithError() throws {
        container = try ModelContainerConfig.makeInMemoryContainer()
        repository = TagRepository(modelContainer: container)
    }

    override func tearDown() {
        container = nil
        repository = nil
    }

    func testFindTagMissesWhenNoneExists() async throws {
        let found = try await repository.findTag(named: "工作")
        XCTAssertNil(found)
    }

    func testFindTagHitsAfterCreate() async throws {
        let id = try await repository.createTag(name: "工作")

        let found = try await repository.findTag(named: "工作")

        XCTAssertEqual(found?.id, id)
        XCTAssertEqual(found?.name, "工作")
    }

    /// 应用层查重：调用方在 `createTag` 前先 `findTag`，同名不应重复创建。
    func testApplicationLevelDedupPreventsDuplicateNames() async throws {
        let name = "生活"

        if try await repository.findTag(named: name) == nil {
            try await repository.createTag(name: name)
        }
        if try await repository.findTag(named: name) == nil {
            try await repository.createTag(name: name)
        }

        let total = try await repository.totalTagCount()
        XCTAssertEqual(total, 1)
    }

    func testCreateOrReuseTagIsAtomicForConcurrentSameName() async throws {
        let repository = try XCTUnwrap(repository)
        let quotaService = QuotaService(
            entitlementProvider: SubscriptionEntitlementProvider(isPro: false)
        )

        async let first = repository.createOrReuseTag(name: "旅行", quotaService: quotaService)
        async let second = repository.createOrReuseTag(name: "旅行", quotaService: quotaService)
        let results = try await [first, second]

        XCTAssertEqual(Set(results.map(\.id)).count, 1)
        XCTAssertEqual(results.filter(\.didCreate).count, 1)
        let total = try await repository.totalTagCount()
        XCTAssertEqual(total, 1)
    }

    func testTotalTagCountReflectsRowCount() async throws {
        try await repository.createTag(name: "工作")
        try await repository.createTag(name: "生活")
        try await repository.createTag(name: "健康")

        let total = try await repository.totalTagCount()

        XCTAssertEqual(total, 3)
    }

    /// 重命名成功：应用层查重通过（新名称未被其它标签占用）。
    func testRenameTagSucceedsWhenNewNameIsUnused() async throws {
        let id = try await repository.createTag(name: "工作")

        try await repository.renameTag(id: id, newName: "副业")

        let renamed = try await repository.findTag(named: "副业")
        XCTAssertEqual(renamed?.id, id)
        let oldNameLookup = try await repository.findTag(named: "工作")
        XCTAssertNil(oldNameLookup, "旧名称不应再命中")
    }

    /// 重命名为「另一个」已存在标签的名称应抛 `tagNameConflict`，不静默、不覆盖。
    func testRenameTagToExistingOtherNameThrowsConflict() async throws {
        let workID = try await repository.createTag(name: "工作")
        _ = try await repository.createTag(name: "生活")

        do {
            try await repository.renameTag(id: workID, newName: "生活")
            XCTFail("期望抛出 RepositoryError.tagNameConflict，但没有抛出")
        } catch RepositoryError.tagNameConflict(let name) {
            XCTAssertEqual(name, "生活")
        } catch {
            XCTFail("期望 RepositoryError.tagNameConflict，实际抛出 \(error)")
        }

        let stillWork = try await repository.findTag(named: "工作")
        XCTAssertEqual(stillWork?.id, workID, "冲突时不应改动原标签")
    }

    /// 重命名为自身原名不算冲突（无实际改动，允许通过）。
    func testRenameTagToOwnCurrentNameIsNotConflict() async throws {
        let id = try await repository.createTag(name: "工作")

        try await repository.renameTag(id: id, newName: "工作")

        let found = try await repository.findTag(named: "工作")
        XCTAssertEqual(found?.id, id)
    }

    /// `id` 不存在应抛 `tagNotFound`，不静默 no-op。
    func testRenameTagOnMissingIDThrows() async throws {
        let missingID = UUID()

        do {
            try await repository.renameTag(id: missingID, newName: "任意名称")
            XCTFail("期望抛出 RepositoryError.tagNotFound，但没有抛出")
        } catch RepositoryError.tagNotFound(let id) {
            XCTAssertEqual(id, missingID)
        } catch {
            XCTFail("期望 RepositoryError.tagNotFound，实际抛出 \(error)")
        }
    }

    func testDeleteTagOnMissingIDThrows() async throws {
        let missingID = UUID()

        do {
            try await repository.deleteTag(id: missingID)
            XCTFail("期望抛出 RepositoryError.tagNotFound，但没有抛出")
        } catch RepositoryError.tagNotFound(let id) {
            XCTAssertEqual(id, missingID)
        } catch {
            XCTFail("期望 RepositoryError.tagNotFound，实际抛出 \(error)")
        }
    }
}
