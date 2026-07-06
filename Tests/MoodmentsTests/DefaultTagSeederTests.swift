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

    /// 首同步去重（见阶段7计划决策3、`docs/design/09-icloud-sync.md`）：模拟「另一台设备已经
    /// 通过 CloudKit 同步预置了部分默认标签」的场景——本地表非空、但并非全部三个默认名都在，
    /// 按名去重应只补齐缺失的那些，而不是因为「非空」就整批跳过、也不会重复创建已存在的。
    func testDeduplicatesByNameWhenSomeDefaultTagsAlreadyExist() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let repository = TagRepository(modelContainer: container)

        // 模拟「工作」标签已由另一台设备同步下来。
        try await repository.createTag(name: "工作")

        try await DefaultTagSeeder.seedIfNeeded(using: repository)

        let names = try await repository.fetchAll().map(\.name)
        XCTAssertEqual(Set(names), Set(DefaultTagSeeder.defaultNames))
        XCTAssertEqual(names.count, DefaultTagSeeder.defaultNames.count, "不应重复创建已存在的「工作」")
    }

    /// CloudKit 已启用时，预置前应等待一次「首次同步信号」或短超时（决策3「短超时兜底」）：
    /// 用可控的 `firstImportSignal` 注入立即完成的信号，验证等待逻辑本身不会无限期阻塞、
    /// 且信号到达后仍然正确按名去重预置。
    func testWaitsForFirstImportSignalWhenCloudKitEnabled() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let repository = TagRepository(modelContainer: container)

        try await DefaultTagSeeder.seedIfNeeded(
            using: repository, cloudKitEnabled: true, firstImportSignal: {}
        )

        let names = try await repository.fetchAll().map(\.name)
        XCTAssertEqual(Set(names), Set(DefaultTagSeeder.defaultNames))
    }
}
