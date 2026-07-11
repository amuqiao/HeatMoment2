import XCTest
@testable import Moodments

/// `DefaultTagSeeder` 测试：首启预置「工作/生活/健康」，非首启永不复活。
final class DefaultTagSeederTests: XCTestCase {
    private func makeIsolatedDefaultsSuiteName() -> String {
        let suiteName = "com.moodments.test.defaultTagSeeder.\(UUID().uuidString)"
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return suiteName
    }

    func testSeedsThreeDefaultTagsOnFirstLaunch() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let suiteName = makeIsolatedDefaultsSuiteName()

        let didSeed = try await DefaultTagSeeder.seedIfNeeded(
            using: fixture.runtime.repository,
            userDefaultsSuiteName: suiteName
        )

        XCTAssertTrue(didSeed)
        let names = try await fixture.runtime.repository.fetchAllTags().map(\.name)
        XCTAssertEqual(names, DefaultTagSeeder.defaultNames)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertTrue(defaults.bool(forKey: DefaultTagSeeder.hasCompletedFirstSeedKey))
    }

    func testDoesNotDuplicateOnSecondLaunch() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let suiteName = makeIsolatedDefaultsSuiteName()

        let firstSeed = try await DefaultTagSeeder.seedIfNeeded(
            using: fixture.runtime.repository,
            userDefaultsSuiteName: suiteName
        )
        let secondSeed = try await DefaultTagSeeder.seedIfNeeded(
            using: fixture.runtime.repository,
            userDefaultsSuiteName: suiteName
        )

        XCTAssertTrue(firstSeed)
        XCTAssertFalse(secondSeed)
        let total = try await fixture.runtime.repository.totalTagCount()
        XCTAssertEqual(total, DefaultTagSeeder.defaultNames.count)
    }

    func testDeletedDefaultTagDoesNotReviveOnNextLaunch() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let suiteName = makeIsolatedDefaultsSuiteName()

        try await DefaultTagSeeder.seedIfNeeded(
            using: fixture.runtime.repository,
            userDefaultsSuiteName: suiteName
        )
        let seeded = try await fixture.runtime.repository.fetchAllTags()
        let workTag = try XCTUnwrap(seeded.first(where: { $0.name == "工作" }))

        try await fixture.runtime.repository.deleteTag(id: workTag.id)
        try await DefaultTagSeeder.seedIfNeeded(
            using: fixture.runtime.repository,
            userDefaultsSuiteName: suiteName
        )

        let namesAfter = try await fixture.runtime.repository.fetchAllTags().map(\.name)
        XCTAssertFalse(namesAfter.contains("工作"), "删除的默认标签不应在下次启动复活")
        XCTAssertEqual(namesAfter.count, DefaultTagSeeder.defaultNames.count - 1)
    }

    func testDeduplicatesByNameWhenSomeDefaultTagsAlreadyExist() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let suiteName = makeIsolatedDefaultsSuiteName()

        _ = try await fixture.runtime.repository.createOrReuseTag(name: "工作")

        try await DefaultTagSeeder.seedIfNeeded(
            using: fixture.runtime.repository,
            userDefaultsSuiteName: suiteName
        )

        let names = try await fixture.runtime.repository.fetchAllTags().map(\.name)
        XCTAssertEqual(Set(names), Set(DefaultTagSeeder.defaultNames))
        XCTAssertEqual(names.count, DefaultTagSeeder.defaultNames.count)
    }

    func testWaitsForFirstImportSignalWhenCloudKitEnabled() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let suiteName = makeIsolatedDefaultsSuiteName()

        try await DefaultTagSeeder.seedIfNeeded(
            using: fixture.runtime.repository,
            cloudKitEnabled: true,
            firstImportSignal: {},
            userDefaultsSuiteName: suiteName
        )

        let names = try await fixture.runtime.repository.fetchAllTags().map(\.name)
        XCTAssertEqual(Set(names), Set(DefaultTagSeeder.defaultNames))
    }

    private func makeFixture() throws -> CanonicalFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "DefaultTagSeederTests-\(UUID().uuidString)",
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
