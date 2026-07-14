import XCTest
@testable import HeatMoment

/// 公理2「定位 ≠ 筛选」验收：
/// - `TimelineLocator.scrollTargetID(for:granularity:in:)` 是纯函数：只挑一个 id，
///   不修改/不重排传入的 `entries`。
/// - `TimelineModel` 的 `heatmapFocusDate` 与 `activeFilter` 是两个独立存储属性，
///   改一个不影响另一个。
final class LocateVsFilterTests: XCTestCase {
    func testScrollTargetIDIsPureAndDoesNotMutateEntries() throws {
        let now = Self.date(year: 2026, month: 4, day: 10, hour: 12)
        let older = Self.entry(
            title: "older",
            occurredAt: Self.date(year: 2026, month: 4, day: 10, hour: 8),
            mood: .sad
        )
        let newer = Self.entry(title: "newer", occurredAt: now, mood: .happy)
        let previousDay = Self.entry(
            title: "previous day",
            occurredAt: Self.date(year: 2026, month: 4, day: 9, hour: 21),
            mood: .normal
        )
        let entries = [newer, previousDay, older]
        let idsBefore = entries.map(\.id)

        let targetID = TimelineLocator.scrollTargetID(for: now, in: entries)

        XCTAssertEqual(targetID, newer.id, "日 anchor 应挑中同日 occurredAt <= date 中最新的一条")
        XCTAssertNotEqual(targetID, previousDay.id, "日 anchor 不应退到前一天记录")
        XCTAssertEqual(entries.map(\.id), idsBefore, "纯函数不应修改/重排传入的 entries")
        XCTAssertNil(
            TimelineLocator.scrollTargetID(for: now.addingTimeInterval(-999_999), in: entries),
            "找不到同日符合条件的条目时应返回 nil"
        )
    }

    func testScrollTargetIDForMonthAnchorTargetsLatestVisibleMomentInThatMonth() throws {
        let aprilFirst = Self.date(year: 2026, month: 4, day: 1, hour: 8)
        let aprilLast = Self.date(year: 2026, month: 4, day: 28, hour: 21)
        let mayMoment = Self.date(year: 2026, month: 5, day: 1, hour: 9)
        let older = Self.entry(title: "april older", occurredAt: aprilFirst, mood: .sad)
        let latest = Self.entry(title: "april latest", occurredAt: aprilLast, mood: .happy)
        let nextMonth = Self.entry(title: "may", occurredAt: mayMoment, mood: .normal)
        let entries = [nextMonth, latest, older]
        let aprilEnd = Self.monthEnd(year: 2026, month: 4)

        let targetID = TimelineLocator.scrollTargetID(
            for: aprilEnd,
            granularity: .month,
            in: entries
        )

        XCTAssertEqual(targetID, latest.id)
        XCTAssertNotEqual(targetID, nextMonth.id, "月 anchor 不应越过该月末刻命中下个月记录")
    }

    func testMonthAnchorReturnsNilWhenCurrentVisibleSetHasNoMomentInThatMonth() throws {
        let mayMoment = Self.entry(
            title: "may visible",
            occurredAt: Self.date(year: 2026, month: 5, day: 1, hour: 9),
            mood: .happy
        )
        let marchMoment = Self.entry(
            title: "march visible",
            occurredAt: Self.date(year: 2026, month: 3, day: 20, hour: 9),
            mood: .happy
        )
        let currentlyVisibleEntries = [mayMoment, marchMoment]

        XCTAssertNil(
            TimelineLocator.scrollTargetID(
                for: Self.monthEnd(year: 2026, month: 4),
                granularity: .month,
                in: currentlyVisibleEntries
            ),
            "月 anchor 不应退到更早月份记录"
        )
    }

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

    private static func entry(title: String, occurredAt: Date, mood: Mood) -> TimelineEntry {
        let id = UUID()
        return TimelineEntry(
            id: id,
            momentID: id,
            title: title,
            bodyText: "",
            mood: mood,
            occurredAt: occurredAt,
            tagNames: [],
            imageIDs: []
        )
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
