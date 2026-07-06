import SwiftData
import XCTest
@testable import Moodments

/// 公理2「定位 ≠ 筛选」验收（见 `docs/product-mental-model.md` 公理2、
/// `docs/plans/implementation-plan.md` 阶段5「正交性的结构保证」）：
/// - `TimelineQuery.predicate(for:)` 签名内没有任何 `Date` 参数——类型层面直接杜绝
///   热力图定位污染数据集，同一 `filter` 下反复取数结果必须完全相等；
/// - `filter` 变化会改变数据集（心情不同则命中不同）；
/// - `TimelineQuery.scrollTargetID(for:in:)` 是纯函数：只挑一个 id，不修改/不重排传入的 `entries`；
/// - `TimelineModel` 的 `heatmapFocusDate` 与 `activeFilter` 是两个独立存储属性，改一个不影响另一个。
final class LocateVsFilterTests: XCTestCase {
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

    /// 同一 `filter` 下，反复用 `TimelineQuery.predicate(for:)` 取数应完全相等——因为该函数
    /// 根本不接受、也不可能读到任何「当前定位到哪一天」的信息，这是公理2在类型层的保证。
    ///
    /// 阶段5 review 修复：此前全程未真正变动 `TimelineModel.heatmapFocusDate`，是个重言式
    /// （"不变的东西不变"）。改为在取数前后**真正把定位状态改到不同值**（`nil` → 某日期 →
    /// 另一个远早于任何记录的日期），断言每次取数结果仍完全相等，才是名副其实地验证
    /// 「改定位不影响筛选取数」。
    @MainActor
    func testPredicateResultStableRegardlessOfLocateState() async throws {
        let now = Date.now
        let happyID = try await repository.createMoment(title: "a", bodyText: "", occurredAt: now, mood: .happy)
        _ = try await repository.createMoment(
            title: "b", bodyText: "", occurredAt: now.addingTimeInterval(-3600), mood: .sad
        )
        let happyID2 = try await repository.createMoment(
            title: "c", bodyText: "", occurredAt: now.addingTimeInterval(-7200), mood: .happy
        )

        let filter = FilterCondition(mood: .happy)
        let context = ModelContext(container)
        let timelineModel = TimelineModel()

        func fetchIDs() throws -> [UUID] {
            let descriptor = FetchDescriptor<Moment>(
                predicate: TimelineQuery.predicate(for: filter),
                sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
            )
            return try context.fetch(descriptor).map(\.id)
        }

        XCTAssertNil(timelineModel.heatmapFocusDate)
        let resultA = try fetchIDs()

        timelineModel.heatmapFocusDate = now
        let resultB = try fetchIDs()

        timelineModel.heatmapFocusDate = now.addingTimeInterval(-999_999)
        let resultC = try fetchIDs()

        XCTAssertEqual(resultA, [happyID, happyID2])
        XCTAssertEqual(resultA, resultB, "定位状态从 nil 改为某日期，筛选取数结果必须不变")
        XCTAssertEqual(resultA, resultC, "定位状态改到另一个日期，筛选取数结果仍必须不变")
    }

    /// `filter` 变化会改变数据集：心情不同则命中不同；`nil` 表示全量（未软删除）。
    func testPredicateChangesWithFilter() async throws {
        let now = Date.now
        let happyID = try await repository.createMoment(title: "a", bodyText: "", occurredAt: now, mood: .happy)
        let sadID = try await repository.createMoment(title: "b", bodyText: "", occurredAt: now, mood: .sad)
        let context = ModelContext(container)

        let happyResult = try context.fetch(
            FetchDescriptor<Moment>(predicate: TimelineQuery.predicate(for: FilterCondition(mood: .happy)))
        ).map(\.id)
        let sadResult = try context.fetch(
            FetchDescriptor<Moment>(predicate: TimelineQuery.predicate(for: FilterCondition(mood: .sad)))
        ).map(\.id)
        let allResult = try context.fetch(
            FetchDescriptor<Moment>(predicate: TimelineQuery.predicate(for: nil))
        ).map(\.id)

        XCTAssertEqual(happyResult, [happyID])
        XCTAssertEqual(sadResult, [sadID])
        XCTAssertEqual(Set(allResult), Set([happyID, sadID]))
    }

    /// `scrollTargetID` 是纯函数：从给定 `entries` 挑「occurredAt <= date」中最新的一条，
    /// 不修改、不重排传入数组本身（只读取，见 `TimelineQuery` 头部说明）。
    func testScrollTargetIDIsPureAndDoesNotMutateEntries() throws {
        let context = ModelContext(container)
        let now = Date.now
        let older = Moment(title: "older", occurredAt: now.addingTimeInterval(-3600), mood: .sad)
        let newer = Moment(title: "newer", occurredAt: now, mood: .happy)
        context.insert(older)
        context.insert(newer)
        try context.save()

        let entries = [TimelineEntry.real(newer), TimelineEntry.real(older)]
        let idsBefore = entries.map(\.id)

        let targetID = TimelineQuery.scrollTargetID(for: now, in: entries)

        XCTAssertEqual(targetID, newer.id, "应挑中 occurredAt <= date 中最新的一条")
        XCTAssertEqual(entries.map(\.id), idsBefore, "纯函数不应修改/重排传入的 entries")
        XCTAssertNil(
            TimelineQuery.scrollTargetID(for: now.addingTimeInterval(-999_999), in: entries),
            "找不到符合条件的条目时应返回 nil"
        )
    }

    /// `TimelineModel` 的定位/筛选是两个独立存储属性：改一个绝不影响另一个的取值（公理2的
    /// 结构化落实，见 `TimelineModel` 头部注释「必要重构」）。
    @MainActor
    func testHeatmapFocusDateAndActiveFilterAreIndependentStorage() {
        let model = TimelineModel()
        XCTAssertNil(model.heatmapFocusDate)
        XCTAssertNil(model.activeFilter)

        model.activeFilter = FilterCondition(mood: .angry)
        XCTAssertNil(model.heatmapFocusDate, "改筛选不应影响定位状态")

        model.heatmapFocusDate = .now
        XCTAssertEqual(model.activeFilter, FilterCondition(mood: .angry), "改定位不应影响筛选状态")

        model.activeFilter = nil
        XCTAssertNotNil(model.heatmapFocusDate, "清空筛选不应影响定位状态")
    }
}
