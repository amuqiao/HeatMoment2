import XCTest
@testable import Moodments

@MainActor
final class CanonicalLibraryServiceTests: XCTestCase {
    func testPrepareWithoutImportMarksServiceReadyAndBumpsChangeToken() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }

        XCTAssertFalse(fixture.service.isPrepared)
        XCTAssertEqual(fixture.service.changeToken, 0)

        try await fixture.service.prepareIfNeeded()

        XCTAssertTrue(fixture.service.isPrepared)
        XCTAssertEqual(fixture.service.changeToken, 1)
    }

    func testServiceReturnsTimelinePreviewAndEditingValueProjections() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let tag = try await fixture.service.repository.createOrReuseTag(
            name: "工作",
            now: Date(timeIntervalSince1970: 10)
        )
        let momentID = try await fixture.service.repository.createMoment(
            title: "标题",
            bodyText: "正文",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .happy,
            tagIDs: [tag.id],
            imageDatas: [Data([0x01]), Data([0x02])],
            now: Date(timeIntervalSince1970: 200)
        )
        fixture.service.noteCanonicalChange()

        let entries = try await fixture.service.fetchTimelineEntries(filter: nil)
        XCTAssertEqual(entries.map(\.momentID), [momentID])
        XCTAssertEqual(entries.first?.tagNames, ["工作"])
        XCTAssertEqual(entries.first?.imageIDs.count, 2)

        let previewData = try await fixture.service.fetchPreviewData(id: momentID)
        XCTAssertEqual(previewData.record.id, momentID)
        XCTAssertEqual(previewData.tagNames, ["工作"])
        XCTAssertEqual(previewData.imageDatas.map(\.data), [Data([0x01]), Data([0x02])])

        let editingPayload = try await fixture.service.editingPayload(id: momentID)
        XCTAssertEqual(editingPayload.snapshot.id, momentID)
        XCTAssertEqual(editingPayload.snapshot.tagIDs, [tag.id])
        XCTAssertEqual(editingPayload.tagNames[tag.id], "工作")
        XCTAssertEqual(editingPayload.imageDatas, [Data([0x01]), Data([0x02])])
    }

    func testCanonicalMutationServiceWritesAndRefreshesChangeToken() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let mutationService = LocalLibraryMutationService(
            canonicalService: fixture.service,
            syncStatusService: SyncStatusService(
                cloudKitEnabled: false,
                reachabilityChecker: CanonicalServiceImmediateReachabilityChecker()
            ),
            errorPresenter: ErrorPresenter()
        )

        let tag = try await mutationService.createOrReuseTag(
            name: "生活",
            quotaService: freeQuotaService()
        )
        XCTAssertEqual(fixture.service.changeToken, 1)

        let momentID = try await mutationService.createMoment(
            title: "今天",
            bodyText: "不错",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .normal,
            tagIDs: [tag.id],
            imageDatas: [],
            quotaService: freeQuotaService()
        )
        XCTAssertEqual(fixture.service.changeToken, 2)

        var entries = try await fixture.service.fetchTimelineEntries(filter: nil)
        XCTAssertEqual(entries.map(\.momentID), [momentID])

        try await mutationService.softDeleteMoment(id: momentID)
        XCTAssertEqual(fixture.service.changeToken, 3)
        entries = try await fixture.service.fetchTimelineEntries(filter: nil)
        XCTAssertTrue(entries.isEmpty)
        let trash = try await fixture.service.fetchTrash()
        XCTAssertEqual(trash.map(\.id), [momentID])
    }

    private func makeFixture() throws -> Fixture {
        let assetDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CanonicalLibraryServiceTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let runtime = try CanonicalLibraryRuntime.makeInMemoryForTests(
            assetDirectoryURL: assetDirectory
        )
        return Fixture(
            service: CanonicalLibraryService(runtime: runtime),
            assetDirectory: assetDirectory
        )
    }

    private func freeQuotaService() -> QuotaService {
        QuotaService(entitlementProvider: SubscriptionEntitlementProvider(isPro: false))
    }
}

private struct Fixture {
    let service: CanonicalLibraryService
    let assetDirectory: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: assetDirectory)
    }
}

private struct CanonicalServiceImmediateReachabilityChecker: NetworkReachabilityChecking {
    func isReachable() async -> Bool { true }
}
