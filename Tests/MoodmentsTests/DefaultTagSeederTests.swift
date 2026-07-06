import XCTest
import SwiftData
@testable import Moodments

/// `DefaultTagSeeder` 测试（见 `docs/design/07-data-persistence.md` §4：首启预置
/// 「工作/生活/健康」，非首启永不复活）。预置经后台 `TagRepository`（08 §5 分层契约）。
///
/// 每个用例使用独立的 `UserDefaults` 隔离套件承载「首启已完成预置」标记（见
/// `DefaultTagSeeder.hasCompletedFirstSeedKey`），避免污染真实 `UserDefaults.standard`、
/// 也避免用例之间互相影响。
final class DefaultTagSeederTests: XCTestCase {
    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "com.moodments.test.defaultTagSeeder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        // 只捕获 `suiteName`（`String`，天然 `Sendable`），不捕获 `defaults` 本身，避免
        // teardown 闭包与测试方法分属不同隔离域时的 data race 编译告警；`removePersistentDomain`
        // 按域名清除，不要求调用方是同一个 `UserDefaults` 实例。
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    func testSeedsThreeDefaultTagsOnFirstLaunch() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let repository = TagRepository(modelContainer: container)
        let defaults = makeIsolatedDefaults()

        try await DefaultTagSeeder.seedIfNeeded(using: repository, userDefaults: defaults)

        let names = try await repository.fetchAll().map(\.name)
        XCTAssertEqual(names, DefaultTagSeeder.defaultNames)
        let hasCompleted = defaults.bool(forKey: DefaultTagSeeder.hasCompletedFirstSeedKey)
        XCTAssertTrue(hasCompleted, "首启预置成功后应置位标记")
    }

    func testDoesNotDuplicateOnSecondLaunch() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let repository = TagRepository(modelContainer: container)
        let defaults = makeIsolatedDefaults()

        try await DefaultTagSeeder.seedIfNeeded(using: repository, userDefaults: defaults)
        try await DefaultTagSeeder.seedIfNeeded(using: repository, userDefaults: defaults)

        let total = try await repository.totalTagCount()
        XCTAssertEqual(total, DefaultTagSeeder.defaultNames.count)
    }

    /// 回归用例（阶段7 review 修复）：`Tag` 是硬删除，用户在首启预置后删掉某个默认标签，
    /// 下次冷启动（`seedIfNeeded` 再次被调用，标记已置位）**不应**把它补回来——否则非 Pro
    /// 用户会被动持有超过免费上限（3）的标签数，绕过 `QuotaService` 判定。
    func testDeletedDefaultTagDoesNotReviveOnNextLaunch() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let repository = TagRepository(modelContainer: container)
        let defaults = makeIsolatedDefaults()

        // 首启：预置三个默认标签。
        try await DefaultTagSeeder.seedIfNeeded(using: repository, userDefaults: defaults)
        let seeded = try await repository.fetchAll()
        guard let workTag = seeded.first(where: { $0.name == "工作" }) else {
            XCTFail("首启应已预置「工作」")
            return
        }

        // 用户删除「工作」标签（硬删除，见 `TagRepository.deleteTag`）。
        try await repository.deleteTag(id: workTag.id)

        // 模拟下一次冷启动：标记已置位，再次调用应直接短路、不重新查询/创建任何标签。
        try await DefaultTagSeeder.seedIfNeeded(using: repository, userDefaults: defaults)

        let namesAfter = try await repository.fetchAll().map(\.name)
        XCTAssertFalse(namesAfter.contains("工作"), "删除的默认标签不应在下次启动复活")
        XCTAssertEqual(namesAfter.count, DefaultTagSeeder.defaultNames.count - 1)
    }

    /// 首同步去重（见阶段7计划决策3、`docs/design/09-icloud-sync.md`）：模拟「另一台设备已经
    /// 通过 CloudKit 同步预置了部分默认标签」的场景——本地表非空、但并非全部三个默认名都在，
    /// 首启窗口内按名去重应只补齐缺失的那些，而不会重复创建已存在的。
    func testDeduplicatesByNameWhenSomeDefaultTagsAlreadyExist() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let repository = TagRepository(modelContainer: container)
        let defaults = makeIsolatedDefaults()

        // 模拟「工作」标签已由另一台设备同步下来。
        try await repository.createTag(name: "工作")

        try await DefaultTagSeeder.seedIfNeeded(using: repository, userDefaults: defaults)

        let names = try await repository.fetchAll().map(\.name)
        XCTAssertEqual(Set(names), Set(DefaultTagSeeder.defaultNames))
        XCTAssertEqual(names.count, DefaultTagSeeder.defaultNames.count, "不应重复创建已存在的「工作」")
    }

    /// CloudKit 已启用时，首启预置前应等待一次「首次同步信号」或短超时（决策3「短超时兜底」）：
    /// 用可控的 `firstImportSignal` 注入立即完成的信号，验证等待逻辑本身不会无限期阻塞、
    /// 且信号到达后仍然正确按名去重预置。
    func testWaitsForFirstImportSignalWhenCloudKitEnabled() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let repository = TagRepository(modelContainer: container)
        let defaults = makeIsolatedDefaults()

        try await DefaultTagSeeder.seedIfNeeded(
            using: repository, cloudKitEnabled: true, firstImportSignal: {}, userDefaults: defaults
        )

        let names = try await repository.fetchAll().map(\.name)
        XCTAssertEqual(Set(names), Set(DefaultTagSeeder.defaultNames))
    }
}
