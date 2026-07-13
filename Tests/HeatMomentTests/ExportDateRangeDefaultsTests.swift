import XCTest
@testable import HeatMoment

final class ExportDateRangeDefaultsTests: XCTestCase {
    func testRecentThreeDaysIncludesCurrentDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let currentDay = calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: 2026,
                month: 7,
                day: 12,
                hour: 23,
                minute: 59
            )
        )!

        let range = ExportDateRangeDefaults.recentThreeDays(
            containing: currentDay,
            calendar: calendar
        )

        XCTAssertEqual(
            range.start,
            calendar.date(
                from: DateComponents(
                    timeZone: calendar.timeZone,
                    year: 2026,
                    month: 7,
                    day: 10
                )
            )
        )
        XCTAssertEqual(
            range.end,
            calendar.date(
                from: DateComponents(
                    timeZone: calendar.timeZone,
                    year: 2026,
                    month: 7,
                    day: 12
                )
            )
        )
    }

    func testRecentThreeDaysUsesCalendarDaysAcrossMonthBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let currentDay = calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: 2026,
                month: 3,
                day: 1,
                hour: 12
            )
        )!

        let range = ExportDateRangeDefaults.recentThreeDays(
            containing: currentDay,
            calendar: calendar
        )

        XCTAssertEqual(
            range.start,
            calendar.date(
                from: DateComponents(
                    timeZone: calendar.timeZone,
                    year: 2026,
                    month: 2,
                    day: 27
                )
            )
        )
        XCTAssertEqual(
            range.end,
            calendar.date(
                from: DateComponents(
                    timeZone: calendar.timeZone,
                    year: 2026,
                    month: 3,
                    day: 1
                )
            )
        )
    }
}
