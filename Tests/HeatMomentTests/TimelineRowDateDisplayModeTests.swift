import XCTest
@testable import HeatMoment

final class TimelineRowDateDisplayModeTests: XCTestCase {
    func testFirstEntryUsesFullDate() {
        let entry = Self.entry(occurredAt: Self.date(month: 7, day: 12, hour: 18))

        XCTAssertEqual(
            TimelineRowDateDisplayMode.resolve(entry: entry, previousEntry: nil),
            .fullDate
        )
    }

    func testSameDayEntryUsesTimeOnly() {
        let previous = Self.entry(occurredAt: Self.date(month: 7, day: 12, hour: 18))
        let current = Self.entry(occurredAt: Self.date(month: 7, day: 12, hour: 9))

        XCTAssertEqual(
            TimelineRowDateDisplayMode.resolve(entry: current, previousEntry: previous),
            .timeOnly
        )
    }

    func testDifferentDayEntryUsesFullDate() {
        let previous = Self.entry(occurredAt: Self.date(month: 7, day: 12, hour: 9))
        let current = Self.entry(occurredAt: Self.date(month: 7, day: 11, hour: 22))

        XCTAssertEqual(
            TimelineRowDateDisplayMode.resolve(entry: current, previousEntry: previous),
            .fullDate
        )
    }

    func testDisplayModeSequenceResetsAtDayBoundary() {
        let entries = [
            Self.entry(occurredAt: Self.date(month: 7, day: 12, hour: 18)),
            Self.entry(occurredAt: Self.date(month: 7, day: 12, hour: 9)),
            Self.entry(occurredAt: Self.date(month: 7, day: 11, hour: 22)),
            Self.entry(occurredAt: Self.date(month: 7, day: 11, hour: 8)),
        ]

        let modes = entries.enumerated().map { index, entry in
            TimelineRowDateDisplayMode.resolve(
                entry: entry,
                previousEntry: index > 0 ? entries[index - 1] : nil
            )
        }

        XCTAssertEqual(modes, [.fullDate, .timeOnly, .fullDate, .timeOnly])
    }

    private static func entry(occurredAt: Date) -> TimelineEntry {
        let id = UUID()
        return TimelineEntry(
            id: id,
            momentID: id,
            title: "测试",
            bodyText: "",
            mood: .happy,
            occurredAt: occurredAt,
            tagNames: [],
            imageIDs: []
        )
    }

    private static func date(month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = hour
        return Calendar.current.date(from: components)!
    }
}
