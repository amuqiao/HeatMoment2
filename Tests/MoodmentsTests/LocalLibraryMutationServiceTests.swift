import XCTest
import SwiftData
@testable import Moodments

/// `LocalLibraryMutationService` 测试：锁住 UI 写入边界的副作用编排，
/// repository 自身合同仍由各 repository 测试单独覆盖。
final class LocalLibraryMutationServiceTests: XCTestCase {
    @MainActor
    func testMomentLifecycleMutationsGoThroughService() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let repository = MomentRepository(modelContainer: container)
        let service = makeService(modelContainer: container)

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
        let trashAfterDelete = try await repository.fetchTrash()
        XCTAssertEqual(trashAfterDelete.map(\.id), [id])
        XCTAssertEqual(trashAfterDelete.first?.isDeleted, true)

        try await service.restoreMoment(id: id)
        let pageAfterRestore = try await repository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(pageAfterRestore.map(\.id), [id])
        XCTAssertEqual(pageAfterRestore.first?.isDeleted, false)

        try await service.softDeleteMoment(id: id)
        let trashBeforePurge = try await repository.fetchTrash()
        let imageIDs = trashBeforePurge.first?.imageIDs ?? []
        try await service.purgeMoment(id: id, imageIDs: imageIDs)

        let totalAfterPurge = try await repository.totalMomentCount()
        XCTAssertEqual(totalAfterPurge, 0)
        let trashAfterPurge = try await repository.fetchTrash()
        XCTAssertTrue(trashAfterPurge.isEmpty)
    }

    @MainActor
    func testCreateMomentChecksQuotaAtServiceBoundary() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let repository = MomentRepository(modelContainer: container)
        let service = makeService(modelContainer: container)
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

        let total = try await repository.totalMomentCount()
        XCTAssertEqual(total, Quota.freeMomentLimit)
        let page = try await repository.fetchPage(offset: 0, limit: Quota.freeMomentLimit + 1)
        XCTAssertFalse(page.contains { $0.title == "overflow" })
    }

    @MainActor
    func testCreateOrReuseTagDeduplicatesWithoutExtraWrite() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let repository = TagRepository(modelContainer: container)
        let service = makeService(modelContainer: container)
        let quotaService = freeQuotaService()

        let first = try await service.createOrReuseTag(name: "工作", quotaService: quotaService)
        XCTAssertTrue(first.didCreate)

        let second = try await service.createOrReuseTag(name: "工作", quotaService: quotaService)
        XCTAssertFalse(second.didCreate)
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(second.name, "工作")

        let total = try await repository.totalTagCount()
        XCTAssertEqual(total, 1)
    }

    @MainActor
    func testCreateTagChecksQuotaAtServiceBoundary() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let repository = TagRepository(modelContainer: container)
        let service = makeService(modelContainer: container)
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

        let total = try await repository.totalTagCount()
        XCTAssertEqual(total, Quota.freeTagLimit)
        let missing = try await repository.findTag(named: "灵感")
        XCTAssertNil(missing)
    }

    @MainActor
    func testDeleteTagKeepsMomentAndClearsAssociation() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let momentRepository = MomentRepository(modelContainer: container)
        let service = makeService(modelContainer: container)

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
        let beforeDelete = try await momentRepository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(beforeDelete.first?.tagIDs, [tag.id])

        try await service.deleteTag(id: tag.id)

        let afterDelete = try await momentRepository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(afterDelete.map(\.id), [momentID])
        XCTAssertEqual(afterDelete.first?.tagIDs, [])
        let totalMoments = try await momentRepository.totalMomentCount()
        XCTAssertEqual(totalMoments, 1)
    }

    @MainActor
    func testSafetyPointFailureStopsRestoreBeforeWrite() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let repository = MomentRepository(modelContainer: container)
        let id = try await repository.createMoment(
            title: "trashed",
            bodyText: "",
            occurredAt: .now,
            mood: .sad
        )
        try await repository.softDelete(id: id)
        let failingBackup = try makeFailingBackupCoordinator(modelContainer: container)
        defer { try? FileManager.default.removeItem(at: failingBackup.rootDirectory) }
        let service = makeService(
            modelContainer: container,
            localBackupCoordinator: failingBackup.coordinator
        )

        do {
            try await service.restoreMoment(id: id)
            XCTFail("期望安全恢复点失败时中止恢复，但没有抛出")
        } catch LocalLibraryMutationError.mutationSafetyPointFailed {
        } catch {
            XCTFail("期望 LocalLibraryMutationError.mutationSafetyPointFailed，实际抛出 \(error)")
        }

        let trash = try await repository.fetchTrash()
        XCTAssertEqual(trash.map(\.id), [id])
        let page = try await repository.fetchPage(offset: 0, limit: 10)
        XCTAssertTrue(page.isEmpty, "安全点失败后不应继续执行恢复写入")
    }

    @MainActor
    func testMissingIDsThrowThroughService() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let service = makeService(modelContainer: container)
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
    private func makeService(
        modelContainer: ModelContainer,
        localBackupCoordinator: LocalBackupCoordinator? = nil
    ) -> LocalLibraryMutationService {
        LocalLibraryMutationService(
            modelContainer: modelContainer,
            localBackupCoordinator: localBackupCoordinator,
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

    private func makeFailingBackupCoordinator(
        modelContainer: ModelContainer
    ) throws -> (coordinator: LocalBackupCoordinator, rootDirectory: URL) {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalLibraryMutationServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        let descriptor = LocalBackupStoreDescriptor(
            rootDirectory: rootDirectory,
            storeFileName: "Missing.store",
            sourceLibraryID: "test-local"
        )
        let coordinator = LocalBackupCoordinator(
            descriptor: descriptor,
            recoveryPointManager: try RecoveryPointManager(
                recoveryDirectory: descriptor.recoveryDirectory
            ),
            countsRepository: RecoveryPointCountsRepository(modelContainer: modelContainer),
            appVersion: "1.0.0",
            schemaVersion: 1,
            stableChangeMinimumInterval: 0
        )
        return (coordinator, rootDirectory)
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
