import XCTest
@testable import Moodments

/// 热力图/心情统计年度聚合验收：日期格用当天最后一条 active 时刻的心情；
/// 软删除不参与聚合；年份候选来自 active 记录发生年份并合并当前年。
final class HeatmapMoodColorTests: XCTestCase {
    func testDayUsesLastMomentOfDayMood() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let repository = fixture.runtime.repository
        let year = 2026
        let morning = Self.date(year: year, month: 4, day: 10, hour: 8)
        let evening = Self.date(year: year, month: 4, day: 10, hour: 22)
        _ = try await repository.createMoment(
            title: "早",
            bodyText: "",
            occurredAt: morning,
            mood: .sad
        )
        _ = try await repository.createMoment(
            title: "晚",
            bodyText: "",
            occurredAt: evening,
            mood: .happy
        )

        let moodByDay = try await repository.moodByDay(year: year, filter: nil)
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: morning)!

        XCTAssertEqual(moodByDay[dayOfYear], .happy)
    }

    func testSoftDeletingLastMomentFallsBackToSecondLatest() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let repository = fixture.runtime.repository
        let year = 2026
        let morning = Self.date(year: year, month: 4, day: 10, hour: 8)
        let evening = Self.date(year: year, month: 4, day: 10, hour: 22)
        _ = try await repository.createMoment(
            title: "早",
            bodyText: "",
            occurredAt: morning,
            mood: .sad
        )
        let eveningID = try await repository.createMoment(
            title: "晚",
            bodyText: "",
            occurredAt: evening,
            mood: .happy
        )

        try await repository.softDeleteMoment(id: eveningID)

        let moodByDay = try await repository.moodByDay(year: year, filter: nil)
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: morning)!

        XCTAssertEqual(moodByDay[dayOfYear], .sad)
    }

    func testAllMomentsOfDaySoftDeletedLeavesDayAbsent() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let repository = fixture.runtime.repository
        let year = 2026
        let day = Self.date(year: year, month: 4, day: 10, hour: 8)
        let id = try await repository.createMoment(
            title: "唯一",
            bodyText: "",
            occurredAt: day,
            mood: .happy
        )
        try await repository.softDeleteMoment(id: id)

        let moodByDay = try await repository.moodByDay(year: year, filter: nil)
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: day)!

        XCTAssertNil(moodByDay[dayOfYear])
    }

    func testAggregationDoesNotLeakAcrossYears() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let repository = fixture.runtime.repository
        let day2025 = Self.date(year: 2025, month: 6, day: 15, hour: 10)
        let day2026 = Self.date(year: 2026, month: 6, day: 15, hour: 10)
        _ = try await repository.createMoment(
            title: "2025",
            bodyText: "",
            occurredAt: day2025,
            mood: .sad
        )
        _ = try await repository.createMoment(
            title: "2026",
            bodyText: "",
            occurredAt: day2026,
            mood: .happy
        )

        let moodByDay2025 = try await repository.moodByDay(year: 2025, filter: nil)
        let moodByDay2026 = try await repository.moodByDay(year: 2026, filter: nil)
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: day2025)!

        XCTAssertEqual(moodByDay2025[dayOfYear], .sad)
        XCTAssertEqual(moodByDay2026[dayOfYear], .happy)
        XCTAssertEqual(moodByDay2025.count, 1)
        XCTAssertEqual(moodByDay2026.count, 1)
    }

    func testFilteredAggregationOnlyCountsMatchingMoments() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let repository = fixture.runtime.repository
        let year = 2026
        let day = Self.date(year: year, month: 7, day: 1, hour: 10)
        _ = try await repository.createMoment(
            title: "开心",
            bodyText: "",
            occurredAt: day,
            mood: .happy
        )
        _ = try await repository.createMoment(
            title: "难过",
            bodyText: "",
            occurredAt: day.addingTimeInterval(-86_400),
            mood: .sad
        )

        let moodByDay = try await repository.moodByDay(
            year: year,
            filter: FilterCondition(mood: .happy)
        )

        XCTAssertEqual(moodByDay.count, 1)
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: day)!
        XCTAssertEqual(moodByDay[dayOfYear], .happy)
    }

    func testMoodCountsAggregatesByMoodRegardlessOfFilterConcept() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let repository = fixture.runtime.repository
        let year = 2026
        let base = Self.date(year: year, month: 8, day: 1, hour: 10)
        _ = try await repository.createMoment(
            title: "a",
            bodyText: "",
            occurredAt: base,
            mood: .happy
        )
        _ = try await repository.createMoment(
            title: "b",
            bodyText: "",
            occurredAt: base.addingTimeInterval(3_600),
            mood: .happy
        )
        _ = try await repository.createMoment(
            title: "c",
            bodyText: "",
            occurredAt: base.addingTimeInterval(7_200),
            mood: .sad
        )

        let counts = try await repository.moodCounts(year: year)

        XCTAssertEqual(counts[.happy], 2)
        XCTAssertEqual(counts[.sad], 1)
        XCTAssertNil(counts[.angry])
    }

    func testAvailableYearsUsesMomentOccurredYearsAndCurrentYear() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let repository = fixture.runtime.repository
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

    func testAvailableYearsIncludesFutureOccurredAtYears() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.runtime.repository.createMoment(
            title: "future",
            bodyText: "",
            occurredAt: Self.date(year: 2028, month: 1, day: 1, hour: 10),
            mood: .motivated
        )

        let years = try await fixture.runtime.repository.availableYears(includingCurrentYear: 2026)

        XCTAssertEqual(years, [2026, 2028])
    }

    func testAvailableYearsDefaultsToCurrentYearWhenNoMomentsExist() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let years = try await fixture.runtime.repository.availableYears(includingCurrentYear: 2026)

        XCTAssertEqual(years, [2026])
    }

    func testAvailableYearsExcludesSoftDeletedOnlyYears() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let deletedID = try await fixture.runtime.repository.createMoment(
            title: "deleted",
            bodyText: "",
            occurredAt: Self.date(year: 2021, month: 1, day: 1, hour: 10),
            mood: .sad
        )
        try await fixture.runtime.repository.softDeleteMoment(id: deletedID)

        let years = try await fixture.runtime.repository.availableYears(includingCurrentYear: 2026)

        XCTAssertEqual(years, [2026])
    }

    @MainActor
    func testHeatmapModelReloadFallsBackWhenSelectedYearDisappears() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let service = CanonicalLibraryService(runtime: fixture.runtime)
        let id = try await fixture.runtime.repository.createMoment(
            title: "future",
            bodyText: "",
            occurredAt: Self.date(year: 2028, month: 1, day: 1, hour: 10),
            mood: .motivated
        )
        let model = YearHeatmapModel(canonicalService: service, year: 2028)
        try await model.load(filter: nil)

        XCTAssertEqual(model.year, 2028)
        XCTAssertEqual(model.availableYears, [2026, 2028])

        try await fixture.runtime.repository.softDeleteMoment(id: id)
        try await model.load(filter: nil)

        XCTAssertEqual(model.year, 2026)
        XCTAssertEqual(model.availableYears, [2026])
    }

    private func makeFixture() throws -> HeatmapCanonicalFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeatmapMoodColorTests-\(UUID().uuidString)", isDirectory: true)
        let runtime = try CanonicalLibraryRuntime.makeInMemoryForTests(
            assetDirectoryURL: directory.appendingPathComponent("Assets", isDirectory: true)
        )
        return HeatmapCanonicalFixture(rootDirectory: directory, runtime: runtime)
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

private struct HeatmapCanonicalFixture {
    let rootDirectory: URL
    let runtime: CanonicalLibraryRuntime

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}
