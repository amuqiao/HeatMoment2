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

    func testTotalTagCountReflectsRowCount() async throws {
        try await repository.createTag(name: "工作")
        try await repository.createTag(name: "生活")
        try await repository.createTag(name: "健康")

        let total = try await repository.totalTagCount()

        XCTAssertEqual(total, 3)
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
