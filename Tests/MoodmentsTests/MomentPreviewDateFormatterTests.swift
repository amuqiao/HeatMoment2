import XCTest
@testable import Moodments

final class MomentPreviewDateFormatterTests: XCTestCase {
    func testOccurredAtTextIncludesMonthDayWeekdayAndTime() throws {
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    timeZone: timeZone,
                    year: 2026,
                    month: 7,
                    day: 9,
                    hour: 16,
                    minute: 4
                )
            )
        )

        XCTAssertEqual(
            MomentPreviewDateFormatters.occurredAtText(for: date, timeZone: timeZone),
            "7月9日 周四 16:04"
        )
    }
}
