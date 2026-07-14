import XCTest
@testable import HeatMoment

final class DefaultLibrarySeederTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: LanguagePreference.storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: LanguagePreference.storageKey)
        super.tearDown()
    }

    func testSeedsThreeDefaultTagsAndMomentsOnFirstLaunch() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let didSeed = try await DefaultLibrarySeeder.seedIfNeeded(using: fixture.runtime.repository)

        XCTAssertTrue(didSeed)
        let tags = try await fixture.runtime.repository.fetchAllTags()
        XCTAssertEqual(tags.map(\.name), DefaultLibrarySeeder.defaultTagNames)
        let moments = try await fixture.runtime.repository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(moments.map(\.title), ["马上创建", "什么是时刻?", "欢迎来到心绪日记~"])
        XCTAssertEqual(moments.map(\.tagIDs.count), [1, 1, 1])
        let momentCount = try await fixture.runtime.repository.totalMomentCount()
        let tagCount = try await fixture.runtime.repository.totalTagCount()
        XCTAssertEqual(momentCount, 3)
        XCTAssertEqual(tagCount, 3)
    }

    func testDoesNotDuplicateOnSecondLaunch() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let firstSeed = try await DefaultLibrarySeeder.seedIfNeeded(using: fixture.runtime.repository)
        let secondSeed = try await DefaultLibrarySeeder.seedIfNeeded(using: fixture.runtime.repository)

        XCTAssertTrue(firstSeed)
        XCTAssertFalse(secondSeed)
        let momentCount = try await fixture.runtime.repository.totalMomentCount()
        let tagCount = try await fixture.runtime.repository.totalTagCount()
        XCTAssertEqual(momentCount, 3)
        XCTAssertEqual(tagCount, 3)
    }

    func testHardDeletedDefaultMomentsDoNotReviveOnNextLaunch() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        _ = try await DefaultLibrarySeeder.seedIfNeeded(using: fixture.runtime.repository)
        let moments = try await fixture.runtime.repository.fetchPage(offset: 0, limit: 10)

        for moment in moments {
            try await fixture.runtime.repository.purgeMoment(id: moment.id)
        }
        let didSeed = try await DefaultLibrarySeeder.seedIfNeeded(using: fixture.runtime.repository)

        XCTAssertFalse(didSeed)
        let momentCount = try await fixture.runtime.repository.totalMomentCount()
        XCTAssertEqual(momentCount, 0)
    }

    func testExistingMomentLibraryIsMarkedSeededWithoutAddingDefaults() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.runtime.repository.createMoment(
            title: "用户自己的时刻",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 1_000),
            mood: .normal
        )

        let didSeed = try await DefaultLibrarySeeder.seedIfNeeded(using: fixture.runtime.repository)

        XCTAssertFalse(didSeed)
        let moments = try await fixture.runtime.repository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(moments.map(\.title), ["用户自己的时刻"])
    }

    func testExistingTagOnlyLibraryIsMarkedSeededWithoutAddingDefaults() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        _ = try await fixture.runtime.repository.createOrReuseTag(name: "旅行")

        let didSeed = try await DefaultLibrarySeeder.seedIfNeeded(using: fixture.runtime.repository)

        XCTAssertFalse(didSeed)
        let moments = try await fixture.runtime.repository.fetchPage(offset: 0, limit: 10)
        let tags = try await fixture.runtime.repository.fetchAllTags()
        XCTAssertTrue(moments.isEmpty)
        XCTAssertEqual(tags.map(\.name), ["旅行"])
    }

    func testSeedsLocalizedContentUsingCurrentLanguage() async throws {
        UserDefaults.standard.set(
            LanguagePreference.english.rawValue,
            forKey: LanguagePreference.storageKey
        )
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        let didSeed = try await DefaultLibrarySeeder.seedIfNeeded(using: fixture.runtime.repository)

        XCTAssertTrue(didSeed)
        let tags = try await fixture.runtime.repository.fetchAllTags()
        let moments = try await fixture.runtime.repository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(tags.map(\.name), ["Work", "Life", "Health"])
        XCTAssertEqual(moments.map(\.title), ["Create Now", "What is a Moment?", "Welcome to HeatMoment"])
    }

    private func makeFixture() throws -> CanonicalFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "DefaultLibrarySeederTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let runtime = try CanonicalLibraryRuntime.makeInMemoryForTests(
            assetDirectoryURL: directory.appendingPathComponent("Assets", isDirectory: true)
        )
        return CanonicalFixture(rootDirectory: directory, runtime: runtime)
    }
}

private struct CanonicalFixture {
    let rootDirectory: URL
    let runtime: CanonicalLibraryRuntime

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}
