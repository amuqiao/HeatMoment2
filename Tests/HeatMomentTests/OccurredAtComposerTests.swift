import XCTest
@testable import HeatMoment

/// 编辑器日期/时间就近浮窗共用的发生时间合成语义：
/// 日期浮窗只改年月日，时间浮窗只改时/分，其余组件必须保持不变。
final class OccurredAtComposerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testMergingDatePreservesTimeComponents() throws {
        var originalComponents = DateComponents()
        originalComponents.year = 2026
        originalComponents.month = 7
        originalComponents.day = 8
        originalComponents.hour = 22
        originalComponents.minute = 24
        originalComponents.second = 35
        let original = try makeDate(originalComponents)

        var pickedDateComponents = DateComponents()
        pickedDateComponents.year = 2024
        pickedDateComponents.month = 2
        pickedDateComponents.day = 29
        pickedDateComponents.hour = 9
        pickedDateComponents.minute = 10
        pickedDateComponents.second = 11
        let pickedDate = try makeDate(pickedDateComponents)

        let merged = OccurredAtComposer.mergingDate(
            pickedDate,
            timeFrom: original,
            calendar: calendar
        )
        let components = dateAndTimeComponents(from: merged)

        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 29)
        XCTAssertEqual(components.hour, 22)
        XCTAssertEqual(components.minute, 24)
        XCTAssertEqual(components.second, 35)
    }

    func testMergingTimePreservesDateComponents() throws {
        var originalComponents = DateComponents()
        originalComponents.year = 2026
        originalComponents.month = 7
        originalComponents.day = 8
        originalComponents.hour = 22
        originalComponents.minute = 24
        originalComponents.second = 35
        let original = try makeDate(originalComponents)

        var pickedTimeComponents = DateComponents()
        pickedTimeComponents.year = 2024
        pickedTimeComponents.month = 2
        pickedTimeComponents.day = 29
        pickedTimeComponents.hour = 6
        pickedTimeComponents.minute = 7
        pickedTimeComponents.second = 8
        let pickedTime = try makeDate(pickedTimeComponents)

        let merged = OccurredAtComposer.mergingTime(
            pickedTime,
            dateFrom: original,
            calendar: calendar
        )
        let components = dateAndTimeComponents(from: merged)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 8)
        XCTAssertEqual(components.hour, 6)
        XCTAssertEqual(components.minute, 7)
        XCTAssertEqual(components.second, 35)
    }

    private func makeDate(_ components: DateComponents) throws -> Date {
        var components = components
        components.timeZone = calendar.timeZone
        let date = calendar.date(
            from: components
        )
        return try XCTUnwrap(date)
    }

    private func dateAndTimeComponents(from date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }
}
