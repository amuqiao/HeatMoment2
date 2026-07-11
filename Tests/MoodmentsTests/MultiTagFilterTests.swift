import XCTest
@testable import Moodments

/// 筛选组合逻辑验收：标签多选 AND 交集、心情单选、标签与心情之间也 AND。
final class MultiTagFilterTests: XCTestCase {
    func testEmptyFilterMatchesEverything() {
        let filter = FilterCondition()
        XCTAssertTrue(filter.matches(tagIDs: [], mood: .happy))
        XCTAssertTrue(filter.matches(tagIDs: [UUID()], mood: .sad))
    }

    func testMultipleTagsRequireIntersectionNotUnion() {
        let workID = UUID()
        let lifeID = UUID()
        let filter = FilterCondition(tagIDs: [workID, lifeID])

        XCTAssertTrue(filter.matches(tagIDs: [workID, lifeID], mood: .normal))
        XCTAssertTrue(filter.matches(tagIDs: [workID, lifeID, UUID()], mood: .normal))
        XCTAssertFalse(filter.matches(tagIDs: [workID], mood: .normal))
        XCTAssertFalse(filter.matches(tagIDs: [], mood: .normal))
    }

    func testMoodFilterIsExclusive() {
        let filter = FilterCondition(mood: .happy)
        XCTAssertTrue(filter.matches(tagIDs: [], mood: .happy))
        XCTAssertFalse(filter.matches(tagIDs: [], mood: .sad))
    }

    func testTagAndMoodCombineWithAnd() {
        let workID = UUID()
        let filter = FilterCondition(tagIDs: [workID], mood: .happy)

        XCTAssertTrue(filter.matches(tagIDs: [workID], mood: .happy))
        XCTAssertFalse(filter.matches(tagIDs: [workID], mood: .sad))
        XCTAssertFalse(filter.matches(tagIDs: [], mood: .happy))
    }

    func testCanonicalAggregationHonorsSameTagIntersectionAsMatches() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let repository = fixture.runtime.repository
        let workID = try await repository.createOrReuseTag(name: "工作")
        let lifeID = try await repository.createOrReuseTag(name: "生活")
        let year = 2026
        let base = Self.date(year: year, month: 3, day: 1)

        _ = try await repository.createMoment(
            title: "both",
            bodyText: "",
            occurredAt: base,
            mood: .happy,
            tagIDs: [workID.id, lifeID.id]
        )
        _ = try await repository.createMoment(
            title: "workOnly",
            bodyText: "",
            occurredAt: base.addingTimeInterval(3_600),
            mood: .happy,
            tagIDs: [workID.id]
        )

        let filter = FilterCondition(tagIDs: [workID.id, lifeID.id])
        let moodByDay = try await repository.moodByDay(year: year, filter: filter)

        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: base)!
        XCTAssertEqual(moodByDay.count, 1)
        XCTAssertEqual(moodByDay[dayOfYear], .happy)
    }

    func testNilFilterAggregatesAllMoments() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let repository = fixture.runtime.repository
        let year = 2026
        let base = Self.date(year: year, month: 5, day: 1)
        _ = try await repository.createMoment(
            title: "a",
            bodyText: "",
            occurredAt: base,
            mood: .happy
        )
        _ = try await repository.createMoment(
            title: "b",
            bodyText: "",
            occurredAt: base.addingTimeInterval(-86_400),
            mood: .sad
        )

        let moodByDay = try await repository.moodByDay(year: year, filter: nil)
        XCTAssertEqual(moodByDay.count, 2)
    }

    private func makeFixture() throws -> MultiTagCanonicalFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultiTagFilterTests-\(UUID().uuidString)", isDirectory: true)
        let runtime = try CanonicalLibraryRuntime.makeInMemoryForTests(
            assetDirectoryURL: directory.appendingPathComponent("Assets", isDirectory: true)
        )
        return MultiTagCanonicalFixture(rootDirectory: directory, runtime: runtime)
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

private struct MultiTagCanonicalFixture {
    let rootDirectory: URL
    let runtime: CanonicalLibraryRuntime

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}
