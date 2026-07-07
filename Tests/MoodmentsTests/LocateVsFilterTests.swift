import SwiftData
import XCTest
@testable import Moodments

/// 公理2「定位 ≠ 筛选」验收（见 `docs/product-mental-model.md` 公理2、
/// `docs/plans/implementation-plan.md` 阶段5「正交性的结构保证」）：
/// - `TimelineQuery.predicate(for:)` 签名内没有任何 `Date` 参数——类型层面直接杜绝
///   热力图定位污染数据集，同一 `filter` 下反复取数结果必须完全相等；
/// - `filter` 变化会改变数据集（心情不同则命中不同）；
/// - `TimelineQuery.scrollTargetID(for:granularity:in:)` 是纯函数：只挑一个 id，不修改/不重排传入的 `entries`；
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
        let now = Self.date(year: 2026, month: 4, day: 10, hour: 12)
        let older = Moment(
            title: "older",
            occurredAt: Self.date(year: 2026, month: 4, day: 10, hour: 8),
            mood: .sad
        )
        let newer = Moment(title: "newer", occurredAt: now, mood: .happy)
        let previousDay = Moment(
            title: "previous day",
            occurredAt: Self.date(year: 2026, month: 4, day: 9, hour: 21),
            mood: .normal
        )
        context.insert(older)
        context.insert(newer)
        context.insert(previousDay)
        try context.save()

        let entries = [TimelineEntry.real(newer), TimelineEntry.real(previousDay), TimelineEntry.real(older)]
        let idsBefore = entries.map(\.id)

        let targetID = TimelineQuery.scrollTargetID(for: now, in: entries)

        XCTAssertEqual(targetID, newer.id, "日 anchor 应挑中同日 occurredAt <= date 中最新的一条")
        XCTAssertNotEqual(targetID, previousDay.id, "日 anchor 不应退到前一天记录")
        XCTAssertEqual(entries.map(\.id), idsBefore, "纯函数不应修改/重排传入的 entries")
        XCTAssertNil(
            TimelineQuery.scrollTargetID(for: now.addingTimeInterval(-999_999), in: entries),
            "找不到同日符合条件的条目时应返回 nil"
        )
    }

    /// 月 anchor 仍只是一种定位粒度：调用方传入该月最后一刻，滚动目标应命中当前可见集里
    /// 该月最新一条真实记录；不生成月份伪节点，也不改变传入数据集。
    func testScrollTargetIDForMonthAnchorTargetsLatestVisibleMomentInThatMonth() throws {
        let context = ModelContext(container)
        let aprilFirst = Self.date(year: 2026, month: 4, day: 1, hour: 8)
        let aprilLast = Self.date(year: 2026, month: 4, day: 28, hour: 21)
        let mayMoment = Self.date(year: 2026, month: 5, day: 1, hour: 9)
        let older = Moment(title: "april older", occurredAt: aprilFirst, mood: .sad)
        let latest = Moment(title: "april latest", occurredAt: aprilLast, mood: .happy)
        let nextMonth = Moment(title: "may", occurredAt: mayMoment, mood: .normal)
        context.insert(older)
        context.insert(latest)
        context.insert(nextMonth)
        try context.save()

        let entries = [TimelineEntry.real(nextMonth), TimelineEntry.real(latest), TimelineEntry.real(older)]
        let aprilEnd = Self.monthEnd(year: 2026, month: 4)

        let targetID = TimelineQuery.scrollTargetID(for: aprilEnd, granularity: .month, in: entries)

        XCTAssertEqual(targetID, latest.id)
        XCTAssertNotEqual(targetID, nextMonth.id, "月 anchor 不应越过该月末刻命中下个月记录")
    }

    /// 当前筛选口径下该月没有可见记录时，定位应返回 nil；不能为了定位偷偷放宽筛选。
    func testMonthAnchorReturnsNilWhenCurrentVisibleSetHasNoMomentInThatMonth() throws {
        let context = ModelContext(container)
        let aprilMoment = Moment(
            title: "april hidden by current visible set",
            occurredAt: Self.date(year: 2026, month: 4, day: 10, hour: 8),
            mood: .sad
        )
        let mayMoment = Moment(
            title: "may visible",
            occurredAt: Self.date(year: 2026, month: 5, day: 1, hour: 9),
            mood: .happy
        )
        context.insert(aprilMoment)
        context.insert(mayMoment)
        try context.save()

        let marchMoment = Moment(
            title: "march visible",
            occurredAt: Self.date(year: 2026, month: 3, day: 20, hour: 9),
            mood: .happy
        )
        context.insert(marchMoment)
        try context.save()

        let currentlyVisibleEntries = [TimelineEntry.real(mayMoment), TimelineEntry.real(marchMoment)]

        XCTAssertNil(
            TimelineQuery.scrollTargetID(
                for: Self.monthEnd(year: 2026, month: 4),
                granularity: .month,
                in: currentlyVisibleEntries
            ),
            "月 anchor 不应退到更早月份记录"
        )
    }

    /// 空态引导卡片只是阅读引导，不是真实 Moment；即使其时间落在定位日期/月内，也不能成为
    /// 热力图滚动目标。
    func testScrollTargetIDIgnoresGuidedEntries() throws {
        let guidedEntries = GuidedMoment.all.map(TimelineEntry.guided)

        XCTAssertNil(
            TimelineQuery.scrollTargetID(for: Date.now, in: guidedEntries),
            "日 anchor 不应命中空态引导卡片"
        )
        XCTAssertNil(
            TimelineQuery.scrollTargetID(
                for: Date.now,
                granularity: .month,
                in: guidedEntries
            ),
            "月 anchor 不应命中空态引导卡片"
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

    /// 月定位粒度仍与筛选独立：设置 month anchor 不应改写 `activeFilter`，改筛选也不应清空 month anchor。
    @MainActor
    func testMonthAnchorAndActiveFilterAreIndependentStorage() {
        let model = TimelineModel()
        let anchorDate = Self.monthEnd(year: 2026, month: 4)
        model.activeFilter = FilterCondition(mood: .happy)

        model.setHeatmapAnchor(anchorDate, granularity: .month)

        XCTAssertEqual(model.activeFilter, FilterCondition(mood: .happy))
        XCTAssertEqual(model.heatmapFocusDate, anchorDate)
        XCTAssertEqual(model.heatmapAnchorGranularity, .month)

        model.activeFilter = FilterCondition(mood: .sad)

        XCTAssertEqual(model.heatmapFocusDate, anchorDate)
        XCTAssertEqual(model.heatmapAnchorGranularity, .month)
    }

    private static func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return Calendar.current.date(from: components)!
    }

    private static func monthEnd(year: Int, month: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let calendar = Calendar.current
        let monthStart = calendar.date(from: components)!
        let monthInterval = calendar.dateInterval(of: .month, for: monthStart)!
        return calendar.date(byAdding: .second, value: -1, to: monthInterval.end)!
    }
}
