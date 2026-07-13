import XCTest
@testable import HeatMoment

/// `LocalLibraryMutationService` 测试：锁住 UI 写入边界的副作用编排。
/// 底层数据源固定为 canonical repository。
final class LocalLibraryMutationServiceTests: XCTestCase {
    @MainActor
    func testMomentLifecycleMutationsGoThroughCanonicalService() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let service = makeService(fixture: fixture)

        let id = try await service.createMoment(
            title: "t",
            bodyText: "b",
            occurredAt: .now,
            mood: .happy,
            tagIDs: [],
            imageDatas: [Data("image".utf8)],
            quotaService: freeQuotaService()
        )

        try await service.softDeleteMoment(id: id)
        let trashAfterDelete = try await fixture.runtime.repository.fetchTrash()
        XCTAssertEqual(trashAfterDelete.map(\.id), [id])

        try await service.restoreMoment(id: id)
        let pageAfterRestore = try await fixture.runtime.repository.fetchPage(
            offset: 0,
            limit: 10
        )
        XCTAssertEqual(pageAfterRestore.map(\.id), [id])
        let trashAfterRestore = try await fixture.runtime.repository.fetchTrash()
        XCTAssertTrue(trashAfterRestore.isEmpty)

        try await service.purgeMoment(id: id, imageIDs: pageAfterRestore.first?.imageIDs ?? [])

        let activeAfterPurge = try await fixture.runtime.repository.fetchPage(
            offset: 0,
            limit: 10
        )
        let purgePending = try await fixture.runtime.repository.fetchPurgePendingMoments()
        XCTAssertTrue(activeAfterPurge.isEmpty)
        XCTAssertEqual(purgePending.map(\.id), [id])
    }

    @MainActor
    func testCreateMomentChecksQuotaAtServiceBoundary() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let service = makeService(fixture: fixture)
        let quotaService = freeQuotaService()

        for index in 0..<Quota.freeMomentLimit {
            _ = try await service.createMoment(
                title: "moment-\(index)",
                bodyText: "",
                occurredAt: .now,
                mood: .normal,
                tagIDs: [],
                imageDatas: [],
                quotaService: quotaService
            )
        }

        do {
            _ = try await service.createMoment(
                title: "overflow",
                bodyText: "",
                occurredAt: .now,
                mood: .normal,
                tagIDs: [],
                imageDatas: [],
                quotaService: quotaService
            )
            XCTFail("期望抛出 LocalLibraryMutationError.quotaExceeded，但没有抛出")
        } catch LocalLibraryMutationError.quotaExceeded(let kind) {
            XCTAssertEqual(kind, .moments)
        } catch {
            XCTFail("期望 LocalLibraryMutationError.quotaExceeded，实际抛出 \(error)")
        }

        let total = try await fixture.runtime.repository.totalMomentCount()
        XCTAssertEqual(total, Quota.freeMomentLimit)
        let page = try await fixture.runtime.repository.fetchPage(
            offset: 0,
            limit: Quota.freeMomentLimit + 1
        )
        XCTAssertFalse(page.contains { $0.title == "overflow" })
    }

    @MainActor
    func testCreateOrReuseTagDeduplicatesWithoutExtraWrite() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let service = makeService(fixture: fixture)
        let quotaService = freeQuotaService()

        let first = try await service.createOrReuseTag(name: "工作", quotaService: quotaService)
        XCTAssertTrue(first.didCreate)

        let second = try await service.createOrReuseTag(name: "工作", quotaService: quotaService)
        XCTAssertFalse(second.didCreate)
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(second.name, "工作")

        let total = try await fixture.runtime.repository.totalTagCount()
        XCTAssertEqual(total, 1)
    }

    @MainActor
    func testCreateTagChecksQuotaAtServiceBoundary() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let service = makeService(fixture: fixture)
        let quotaService = freeQuotaService()

        _ = try await service.createOrReuseTag(name: "工作", quotaService: quotaService)
        _ = try await service.createOrReuseTag(name: "生活", quotaService: quotaService)
        _ = try await service.createOrReuseTag(name: "健康", quotaService: quotaService)

        do {
            _ = try await service.createOrReuseTag(name: "灵感", quotaService: quotaService)
            XCTFail("期望抛出 LocalLibraryMutationError.quotaExceeded，但没有抛出")
        } catch LocalLibraryMutationError.quotaExceeded(let kind) {
            XCTAssertEqual(kind, .tags)
        } catch {
            XCTFail("期望 LocalLibraryMutationError.quotaExceeded，实际抛出 \(error)")
        }

        let total = try await fixture.runtime.repository.totalTagCount()
        XCTAssertEqual(total, Quota.freeTagLimit)
        let missing = try await fixture.runtime.repository.findTag(named: "灵感")
        XCTAssertNil(missing)
    }

    @MainActor
    func testDeleteTagKeepsMomentAndClearsAssociation() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let service = makeService(fixture: fixture)

        let tag = try await service.createOrReuseTag(
            name: "工作",
            quotaService: freeQuotaService()
        )
        let momentID = try await service.createMoment(
            title: "t",
            bodyText: "b",
            occurredAt: .now,
            mood: .normal,
            tagIDs: [tag.id],
            imageDatas: [],
            quotaService: freeQuotaService()
        )
        let beforeDelete = try await fixture.runtime.repository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(beforeDelete.first?.tagIDs, [tag.id])

        try await service.deleteTag(id: tag.id)

        let afterDelete = try await fixture.runtime.repository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(afterDelete.map(\.id), [momentID])
        XCTAssertEqual(afterDelete.first?.tagIDs, [])
        let totalMoments = try await fixture.runtime.repository.totalMomentCount()
        XCTAssertEqual(totalMoments, 1)
    }

    @MainActor
    func testMissingIDsThrowThroughService() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let service = makeService(fixture: fixture)
        let missingID = UUID()

        await assertThrowsMomentNotFound(missingID) {
            try await service.softDeleteMoment(id: missingID)
        }
        await assertThrowsMomentNotFound(missingID) {
            try await service.restoreMoment(id: missingID)
        }
        await assertThrowsMomentNotFound(missingID) {
            try await service.purgeMoment(id: missingID, imageIDs: [])
        }
        await assertThrowsMomentNotFound(missingID) {
            try await service.updateMoment(
                id: missingID,
                title: "x",
                bodyText: "",
                occurredAt: .now,
                mood: .normal,
                tagIDs: [],
                imageDatas: [],
                replacingOriginalImageIDs: []
            )
        }

        await assertThrowsTagNotFound(missingID) {
            try await service.renameTag(id: missingID, newName: "x")
        }
        await assertThrowsTagNotFound(missingID) {
            try await service.deleteTag(id: missingID)
        }
    }

    @MainActor
    func testCanonicalBackendCreatesStableRecoveryPointThroughCoordinator() async throws {
        let fixture = try makeFixture(recoveryBacked: true)
        defer { fixture.cleanup() }
        let service = makeService(fixture: fixture)

        _ = try await service.createMoment(
            title: "canonical",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .normal,
            tagIDs: [],
            imageDatas: [],
            quotaService: freeQuotaService()
        )

        let points = try await waitForCanonicalRecoveryPoints(
            coordinator: fixture.coordinator,
            expectedCount: 1
        )
        XCTAssertEqual(points.map(\.reason), [.stableChanges])
        XCTAssertEqual(points.first?.counts.recordCount, 1)
    }

    @MainActor
    func testCanonicalBackendCreatesSafetyPointBeforeHighRiskMutation() async throws {
        let fixture = try makeFixture(recoveryBacked: true)
        defer { fixture.cleanup() }
        let service = makeService(fixture: fixture)
        let id = try await fixture.runtime.repository.createMoment(
            title: "trashed",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .sad
        )
        try await fixture.runtime.repository.softDeleteMoment(id: id)

        try await service.restoreMoment(id: id)

        let points = try await fixture.coordinator.listRecoveryPoints()
        XCTAssertEqual(points.map(\.reason), [.mutationSafety])
        XCTAssertEqual(points.first?.counts.recordCount, 1)
    }

    @MainActor
    private func makeService(fixture: CanonicalFixture) -> LocalLibraryMutationService {
        LocalLibraryMutationService(
            canonicalService: fixture.service,
            canonicalRecoveryCoordinator: fixture.coordinator,
            syncStatusService: SyncStatusService(
                cloudKitEnabled: false,
                reachabilityChecker: ImmediateReachabilityChecker()
            ),
            errorPresenter: ErrorPresenter()
        )
    }

    @MainActor
    private func freeQuotaService() -> QuotaService {
        QuotaService(entitlementProvider: SubscriptionEntitlementProvider(isPro: false))
    }

    @MainActor
    private func makeFixture(recoveryBacked: Bool = false) throws -> CanonicalFixture {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "LocalLibraryMutationCanonicalTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let runtime: CanonicalLibraryRuntime
        if recoveryBacked {
            runtime = try CanonicalLibraryRuntime(
                descriptor: CanonicalStoreDescriptor(rootDirectory: rootDirectory)
            )
        } else {
            runtime = try CanonicalLibraryRuntime.makeInMemoryForTests(
                assetDirectoryURL: rootDirectory.appendingPathComponent(
                    "Assets",
                    isDirectory: true
                )
            )
        }
        let service = CanonicalLibraryService(runtime: runtime)
        let coordinator = CanonicalRecoveryCoordinator(
            runtime: runtime,
            appVersion: "1.0.0",
            stableChangeMinimumInterval: 0
        )
        return CanonicalFixture(
            runtime: runtime,
            service: service,
            coordinator: coordinator,
            rootDirectory: rootDirectory
        )
    }

    @MainActor
    private func waitForCanonicalRecoveryPoints(
        coordinator: CanonicalRecoveryCoordinator,
        expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [CanonicalRecoveryPointRecord] {
        for _ in 0..<20 {
            let points = try await coordinator.listRecoveryPoints()
            if points.count >= expectedCount {
                return points
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        let points = try await coordinator.listRecoveryPoints()
        XCTAssertEqual(points.count, expectedCount, file: file, line: line)
        return points
    }

    @MainActor
    private func assertThrowsMomentNotFound(
        _ id: UUID,
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("期望抛出 RepositoryError.momentNotFound，但没有抛出", file: file, line: line)
        } catch RepositoryError.momentNotFound(let notFoundID) {
            XCTAssertEqual(notFoundID, id, file: file, line: line)
        } catch {
            XCTFail("期望 RepositoryError.momentNotFound，实际抛出 \(error)", file: file, line: line)
        }
    }

    @MainActor
    private func assertThrowsTagNotFound(
        _ id: UUID,
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("期望抛出 RepositoryError.tagNotFound，但没有抛出", file: file, line: line)
        } catch RepositoryError.tagNotFound(let notFoundID) {
            XCTAssertEqual(notFoundID, id, file: file, line: line)
        } catch {
            XCTFail("期望 RepositoryError.tagNotFound，实际抛出 \(error)", file: file, line: line)
        }
    }
}

private struct ImmediateReachabilityChecker: NetworkReachabilityChecking {
    func isReachable() async -> Bool { true }
}

private struct CanonicalFixture {
    let runtime: CanonicalLibraryRuntime
    let service: CanonicalLibraryService
    let coordinator: CanonicalRecoveryCoordinator
    let rootDirectory: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}
