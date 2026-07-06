import SwiftData
import XCTest
@testable import Moodments

/// 筛选组合逻辑验收（见 `docs/design/04-screen-specs.md` §4.2、
/// `docs/design/13-open-questions.md` #19：标签多选 AND 交集、心情单选、标签与心情之间也 AND）。
final class MultiTagFilterTests: XCTestCase {
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

    // MARK: - 纯函数 FilterCondition.matches

    func testEmptyFilterMatchesEverything() {
        let filter = FilterCondition()
        XCTAssertTrue(filter.matches(tagIDs: [], mood: .happy))
        XCTAssertTrue(filter.matches(tagIDs: [UUID()], mood: .sad))
    }

    /// 多标签 AND 交集：必须同时命中全部选中标签，命中标签子集不算。
    func testMultipleTagsRequireIntersectionNotUnion() {
        let workID = UUID()
        let lifeID = UUID()
        let filter = FilterCondition(tagIDs: [workID, lifeID])

        XCTAssertTrue(filter.matches(tagIDs: [workID, lifeID], mood: .normal), "同时挂两个标签应命中")
        XCTAssertTrue(filter.matches(tagIDs: [workID, lifeID, UUID()], mood: .normal), "多挂其它标签不影响命中")
        XCTAssertFalse(filter.matches(tagIDs: [workID], mood: .normal), "只挂其中一个标签不应命中（AND 交集非并集）")
        XCTAssertFalse(filter.matches(tagIDs: [], mood: .normal), "不挂任何标签不应命中")
    }

    /// 心情单选：与筛选心情不同即不命中。
    func testMoodFilterIsExclusive() {
        let filter = FilterCondition(mood: .happy)
        XCTAssertTrue(filter.matches(tagIDs: [], mood: .happy))
        XCTAssertFalse(filter.matches(tagIDs: [], mood: .sad))
    }

    /// 标签维度与心情维度也是 AND：必须同时满足。
    func testTagAndMoodCombineWithAnd() {
        let workID = UUID()
        let filter = FilterCondition(tagIDs: [workID], mood: .happy)

        XCTAssertTrue(filter.matches(tagIDs: [workID], mood: .happy))
        XCTAssertFalse(filter.matches(tagIDs: [workID], mood: .sad), "标签命中但心情不命中，整体不应命中")
        XCTAssertFalse(filter.matches(tagIDs: [], mood: .happy), "心情命中但标签不命中，整体不应命中")
    }

    // MARK: - 经仓库路径对照防漂移

    /// 用真实 SwiftData 路径（`MomentRepository.moodByDay(year:filter:)`）验证标签 AND 交集口径
    /// 与纯函数 `FilterCondition.matches` 完全一致，防止两处各自实现一遍产生漂移
    /// （见 `docs/plans/implementation-plan.md` 阶段5「测试」段）。
    func testRepositoryAggregationHonorsSameTagIntersectionAsMatches() async throws {
        let workID = try await tagRepository.createTag(name: "工作")
        let lifeID = try await tagRepository.createTag(name: "生活")
        let year = 2026
        let base = Self.date(year: year, month: 3, day: 1)

        // 命中：同时挂「工作」+「生活」。
        _ = try await repository.createMoment(
            title: "both", bodyText: "", occurredAt: base, mood: .happy, tagIDs: [workID, lifeID]
        )
        // 不命中：只挂「工作」（AND 交集要求同时挂全部选中标签）。
        _ = try await repository.createMoment(
            title: "workOnly", bodyText: "", occurredAt: base.addingTimeInterval(3600), mood: .happy,
            tagIDs: [workID]
        )

        let filter = FilterCondition(tagIDs: [workID, lifeID])
        let moodByDay = try await repository.moodByDay(year: year, filter: filter)

        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: base)!
        XCTAssertEqual(moodByDay.count, 1, "只有同时挂两个标签的那一条应参与聚合")
        XCTAssertEqual(moodByDay[dayOfYear], .happy)
    }

    /// 空 filter（`nil`）= 全量，不因未选标签/心情而漏掉任何记录。
    func testNilFilterAggregatesAllMoments() async throws {
        let year = 2026
        let base = Self.date(year: year, month: 5, day: 1)
        _ = try await repository.createMoment(title: "a", bodyText: "", occurredAt: base, mood: .happy)
        _ = try await repository.createMoment(
            title: "b", bodyText: "", occurredAt: base.addingTimeInterval(-86400), mood: .sad
        )

        let moodByDay = try await repository.moodByDay(year: year, filter: nil)
        XCTAssertEqual(moodByDay.count, 2)
    }

    private static func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)!
    }
}
