import XCTest
import SwiftData
@testable import Moodments

/// `DefaultTagSeeder` 测试（见 `docs/design/07-data-persistence.md` §4：首启预置
/// 「工作/生活/健康」，非首次不重复）。
final class DefaultTagSeederTests: XCTestCase {
    @MainActor
    func testSeedsThreeDefaultTagsOnEmpty() throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let context = ModelContext(container)

        try DefaultTagSeeder.seedIfNeeded(context)

        let tags = try context.fetch(FetchDescriptor<Tag>(sortBy: [SortDescriptor(\.createdAt)]))
        XCTAssertEqual(tags.map(\.name), DefaultTagSeeder.defaultNames)
    }

    @MainActor
    func testDoesNotDuplicateOnSecondLaunch() throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let context = ModelContext(container)

        try DefaultTagSeeder.seedIfNeeded(context)
        try DefaultTagSeeder.seedIfNeeded(context)

        let total = try context.fetchCount(FetchDescriptor<Tag>())
        XCTAssertEqual(total, DefaultTagSeeder.defaultNames.count)
    }
}
