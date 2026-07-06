import XCTest
import SwiftData
@testable import Moodments

/// `DefaultTagSeeder` 测试（见 `docs/design/07-data-persistence.md` §4：首启预置
/// 「工作/生活/健康」，非首次不重复）。预置经后台 `TagRepository`（08 §5 分层契约）。
final class DefaultTagSeederTests: XCTestCase {
    func testSeedsThreeDefaultTagsOnEmpty() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let repository = TagRepository(modelContainer: container)

        try await DefaultTagSeeder.seedIfNeeded(using: repository)

        let names = try await repository.fetchAll().map(\.name)
        XCTAssertEqual(names, DefaultTagSeeder.defaultNames)
    }

    func testDoesNotDuplicateOnSecondLaunch() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let repository = TagRepository(modelContainer: container)

        try await DefaultTagSeeder.seedIfNeeded(using: repository)
        try await DefaultTagSeeder.seedIfNeeded(using: repository)

        let total = try await repository.totalTagCount()
        XCTAssertEqual(total, DefaultTagSeeder.defaultNames.count)
    }
}
