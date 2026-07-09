import SwiftData
import XCTest
@testable import Moodments

/// 热力图/心情统计年度聚合验收（见 `docs/product-mental-model.md` 公理1「心情色一致性」、
/// `docs/design/04-screen-specs.md` §4.3、`docs/plans/implementation-plan.md` 阶段5）：
/// 日期格用「当天最后一条时刻的心情」着色；软删除不参与聚合（公理3）；不跨年；
/// 接 `filter` 时只统计命中条件的记录。
final class HeatmapMoodColorTests: XCTestCase {
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

    /// 依公理1：日期格用「当天最后一条时刻的心情色」，同一天多条记录时取 occurredAt 最晚的一条。
    func testDayUsesLastMomentOfDayMood() async throws {
        let year = 2026
        let morning = Self.date(year: year, month: 4, day: 10, hour: 8)
        let evening = Self.date(year: year, month: 4, day: 10, hour: 22)
        _ = try await repository.createMoment(title: "早", bodyText: "", occurredAt: morning, mood: .sad)
        _ = try await repository.createMoment(title: "晚", bodyText: "", occurredAt: evening, mood: .happy)

        let moodByDay = try await repository.moodByDay(year: year, filter: nil)
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: morning)!

        XCTAssertEqual(moodByDay[dayOfYear], .happy, "应取当天最晚一条（晚上）的心情")
    }

    /// 软删除当天最后一条后，应回落到当天次晚的一条（软删除的记录不参与聚合，见公理3）。
    func testSoftDeletingLastMomentFallsBackToSecondLatest() async throws {
        let year = 2026
        let morning = Self.date(year: year, month: 4, day: 10, hour: 8)
        let evening = Self.date(year: year, month: 4, day: 10, hour: 22)
        _ = try await repository.createMoment(title: "早", bodyText: "", occurredAt: morning, mood: .sad)
        let eveningID = try await repository.createMoment(
            title: "晚", bodyText: "", occurredAt: evening, mood: .happy
        )

        try await repository.softDelete(id: eveningID)

        let moodByDay = try await repository.moodByDay(year: year, filter: nil)
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: morning)!

        XCTAssertEqual(moodByDay[dayOfYear], .sad, "最晚一条被软删除后应回落到次晚的一条")
    }

    /// 当天全部记录都被软删除后，该日应从聚合结果中缺席（没有 key），而不是留一个默认值。
    func testAllMomentsOfDaySoftDeletedLeavesDayAbsent() async throws {
        let year = 2026
        let day = Self.date(year: year, month: 4, day: 10, hour: 8)
        let id = try await repository.createMoment(title: "唯一", bodyText: "", occurredAt: day, mood: .happy)
        try await repository.softDelete(id: id)

        let moodByDay = try await repository.moodByDay(year: year, filter: nil)
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: day)!

        XCTAssertNil(moodByDay[dayOfYear], "全部软删除后该日不应出现在聚合结果里")
    }

    /// 跨年不串：不同年份同月同日的记录只应出现在各自年份的聚合结果里。
    func testAggregationDoesNotLeakAcrossYears() async throws {
        let day2025 = Self.date(year: 2025, month: 6, day: 15, hour: 10)
        let day2026 = Self.date(year: 2026, month: 6, day: 15, hour: 10)
        _ = try await repository.createMoment(title: "2025", bodyText: "", occurredAt: day2025, mood: .sad)
        _ = try await repository.createMoment(title: "2026", bodyText: "", occurredAt: day2026, mood: .happy)

        let moodByDay2025 = try await repository.moodByDay(year: 2025, filter: nil)
        let moodByDay2026 = try await repository.moodByDay(year: 2026, filter: nil)
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: day2025)!

        XCTAssertEqual(moodByDay2025[dayOfYear], .sad)
        XCTAssertEqual(moodByDay2026[dayOfYear], .happy)
        XCTAssertEqual(moodByDay2025.count, 1, "2025 年聚合不应包含 2026 年的记录")
        XCTAssertEqual(moodByDay2026.count, 1, "2026 年聚合不应包含 2025 年的记录")
    }

    /// 接 `filter` 时只统计命中条件的记录（见阶段5计划决策1：热力图跟随 `activeFilter` 口径）。
    func testFilteredAggregationOnlyCountsMatchingMoments() async throws {
        let year = 2026
        let day = Self.date(year: year, month: 7, day: 1, hour: 10)
        _ = try await repository.createMoment(title: "开心", bodyText: "", occurredAt: day, mood: .happy)
        _ = try await repository.createMoment(
            title: "难过", bodyText: "", occurredAt: day.addingTimeInterval(-86400), mood: .sad
        )

        let moodByDay = try await repository.moodByDay(year: year, filter: FilterCondition(mood: .happy))

        XCTAssertEqual(moodByDay.count, 1, "只有命中筛选条件（开心）的记录应参与聚合")
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: day)!
        XCTAssertEqual(moodByDay[dayOfYear], .happy)
    }

    /// `moodCounts` 恒为全量（不接 filter，供 `MoodStatsView` 使用，见 04 §4.12）。
    func testMoodCountsAggregatesByMoodRegardlessOfFilterConcept() async throws {
        let year = 2026
        let base = Self.date(year: year, month: 8, day: 1, hour: 10)
        _ = try await repository.createMoment(title: "a", bodyText: "", occurredAt: base, mood: .happy)
        _ = try await repository.createMoment(
            title: "b", bodyText: "", occurredAt: base.addingTimeInterval(3600), mood: .happy
        )
        _ = try await repository.createMoment(
            title: "c", bodyText: "", occurredAt: base.addingTimeInterval(7200), mood: .sad
        )

        let counts = try await repository.moodCounts(year: year)

        XCTAssertEqual(counts[.happy], 2)
        XCTAssertEqual(counts[.sad], 1)
        XCTAssertNil(counts[.angry])
    }

    /// 年份候选来自真实未删除记录的发生年份，并始终合并当前年。
    func testAvailableYearsUsesMomentOccurredYearsAndCurrentYear() async throws {
        _ = try await repository.createMoment(
            title: "old",
            bodyText: "",
            occurredAt: Self.date(year: 2022, month: 3, day: 1, hour: 10),
            mood: .normal
        )
        _ = try await repository.createMoment(
            title: "recent",
            bodyText: "",
            occurredAt: Self.date(year: 2025, month: 9, day: 1, hour: 10),
            mood: .happy
        )

        let years = try await repository.availableYears(includingCurrentYear: 2026)

        XCTAssertEqual(years, [2022, 2025, 2026])
    }

    /// 发生时间允许未来日期，年份候选也应跟随真实记录年份扩展。
    func testAvailableYearsIncludesFutureOccurredAtYears() async throws {
        _ = try await repository.createMoment(
            title: "future",
            bodyText: "",
            occurredAt: Self.date(year: 2028, month: 1, day: 1, hour: 10),
            mood: .motivated
        )

        let years = try await repository.availableYears(includingCurrentYear: 2026)

        XCTAssertEqual(years, [2026, 2028])
    }

    /// 无记录时年份菜单不能为空，默认只提供当前年。
    func testAvailableYearsDefaultsToCurrentYearWhenNoMomentsExist() async throws {
        let years = try await repository.availableYears(includingCurrentYear: 2026)

        XCTAssertEqual(years, [2026])
    }

    /// 软删除记录不参与热力图/统计页聚合，也不应撑出一个可选年份。
    func testAvailableYearsExcludesSoftDeletedOnlyYears() async throws {
        let deletedID = try await repository.createMoment(
            title: "deleted",
            bodyText: "",
            occurredAt: Self.date(year: 2021, month: 1, day: 1, hour: 10),
            mood: .sad
        )
        try await repository.softDelete(id: deletedID)

        let years = try await repository.availableYears(includingCurrentYear: 2026)

        XCTAssertEqual(years, [2026])
    }

    /// 派生 model 每次加载都重算候选；选中年份失效时回落到当前年，避免菜单残留空年份。
    func testHeatmapModelReloadFallsBackWhenSelectedYearDisappears() async throws {
        let id = try await repository.createMoment(
            title: "future",
            bodyText: "",
            occurredAt: Self.date(year: 2028, month: 1, day: 1, hour: 10),
            mood: .motivated
        )
        let modelContainer = try XCTUnwrap(container)
        let model = await MainActor.run {
            YearHeatmapModel(modelContainer: modelContainer, year: 2028)
        }
        try await model.load(filter: nil)

        let loadedState = await MainActor.run {
            (year: model.year, availableYears: model.availableYears)
        }
        XCTAssertEqual(loadedState.year, 2028)
        XCTAssertEqual(loadedState.availableYears, [2026, 2028])

        try await repository.softDelete(id: id)
        try await model.load(filter: nil)

        let reloadedState = await MainActor.run {
            (year: model.year, availableYears: model.availableYears)
        }
        XCTAssertEqual(reloadedState.year, 2026)
        XCTAssertEqual(reloadedState.availableYears, [2026])
    }

    private static func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return Calendar.current.date(from: components)!
    }
}
