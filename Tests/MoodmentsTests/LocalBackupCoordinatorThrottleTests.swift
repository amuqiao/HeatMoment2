import SwiftData
import XCTest
@testable import Moodments

final class LocalBackupCoordinatorThrottleTests: RecoveryPointTestCase {
    private let interval: TimeInterval = 60

    func testStableChangeRecoveryPointSkipsWithinMinimumInterval() async throws {
        let descriptor = try makeDescriptor()
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let manager = try RecoveryPointManager(
            recoveryDirectory: descriptor.recoveryDirectory
        )
        let coordinator = makeCoordinator(
            descriptor: descriptor,
            manager: manager,
            container: container
        )

        let first = try await coordinator.createStableChangesRecoveryPointIfNeeded(
            createdAt: date(300)
        )
        let second = try await coordinator.createStableChangesRecoveryPointIfNeeded(
            createdAt: date(320)
        )
        let third = try await coordinator.createStableChangesRecoveryPointIfNeeded(
            createdAt: date(361)
        )

        XCTAssertNotNil(first)
        XCTAssertNil(second)
        XCTAssertNotNil(third)
        let listed = try await manager.listRecoveryPoints()
        XCTAssertEqual(listed.count, 2)
        XCTAssertEqual(listed.map(\.id), [third?.id, first?.id])
        XCTAssertEqual(listed.map(\.reason), [.stableChanges, .stableChanges])
    }

    func testStableChangeThrottleLoadsLatestPointAcrossCoordinatorInstances() async throws {
        let descriptor = try makeDescriptor()
        let container = try ModelContainerConfig.makeInMemoryContainer()

        let firstManager = try RecoveryPointManager(
            recoveryDirectory: descriptor.recoveryDirectory
        )
        let firstCoordinator = makeCoordinator(
            descriptor: descriptor,
            manager: firstManager,
            container: container
        )
        let first = try await firstCoordinator.createStableChangesRecoveryPointIfNeeded(
            createdAt: date(500)
        )

        let restartedManager = try RecoveryPointManager(
            recoveryDirectory: descriptor.recoveryDirectory
        )
        let restartedCoordinator = makeCoordinator(
            descriptor: descriptor,
            manager: restartedManager,
            container: container
        )
        let skippedAfterRestart =
            try await restartedCoordinator.createStableChangesRecoveryPointIfNeeded(
                createdAt: date(520)
            )
        let createdAfterWindow =
            try await restartedCoordinator.createStableChangesRecoveryPointIfNeeded(
                createdAt: date(561)
            )

        XCTAssertNotNil(first)
        XCTAssertNil(skippedAfterRestart)
        XCTAssertNotNil(createdAfterWindow)
        let listed = try await restartedManager.listRecoveryPoints()
        XCTAssertEqual(listed.count, 2)
        XCTAssertEqual(listed.map(\.id), [createdAfterWindow?.id, first?.id])
    }

    func testConcurrentStableChangeRequestsCreateOnlyOneRecoveryPoint() async throws {
        let descriptor = try makeDescriptor()
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let manager = try RecoveryPointManager(
            recoveryDirectory: descriptor.recoveryDirectory
        )
        let coordinator = makeCoordinator(
            descriptor: descriptor,
            manager: manager,
            container: container
        )

        let createdAt = Date(timeIntervalSince1970: 600)
        async let first = coordinator.createStableChangesRecoveryPointIfNeeded(
            createdAt: createdAt
        )
        async let second = coordinator.createStableChangesRecoveryPointIfNeeded(
            createdAt: createdAt
        )

        let firstResult = try await first
        let secondResult = try await second
        let created = [firstResult, secondResult].compactMap { $0 }
        XCTAssertEqual(created.count, 1)
        let listed = try await manager.listRecoveryPoints()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.reason, .stableChanges)
    }

    func testMutationSafetyRecoveryPointBypassesStableChangeThrottle() async throws {
        let descriptor = try makeDescriptor()
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let manager = try RecoveryPointManager(
            recoveryDirectory: descriptor.recoveryDirectory
        )
        let coordinator = makeCoordinator(
            descriptor: descriptor,
            manager: manager,
            container: container
        )

        let stable = try await coordinator.createStableChangesRecoveryPointIfNeeded(
            createdAt: date(400)
        )
        let safety = try await coordinator.createMutationSafetyRecoveryPoint(
            createdAt: date(401)
        )
        let skipped = try await coordinator.createStableChangesRecoveryPointIfNeeded(
            createdAt: date(402)
        )

        XCTAssertNotNil(stable)
        XCTAssertEqual(safety.reason, .mutationSafety)
        XCTAssertNil(skipped)
        let listed = try await manager.listRecoveryPoints()
        XCTAssertEqual(listed.map(\.id), [safety.id, stable?.id])
        XCTAssertEqual(listed.map(\.reason), [.mutationSafety, .stableChanges])
    }

    private func makeDescriptor() throws -> LocalBackupStoreDescriptor {
        let libraryDirectory = try makeSourceDirectory()
        let descriptor = LocalBackupStoreDescriptor(
            rootDirectory: libraryDirectory,
            storeFileName: "Moodments.store",
            sourceLibraryID: "test-local"
        )
        try write("store", to: descriptor.storeURL)
        return descriptor
    }

    private func makeCoordinator(
        descriptor: LocalBackupStoreDescriptor,
        manager: RecoveryPointManager,
        container: ModelContainer
    ) -> LocalBackupCoordinator {
        LocalBackupCoordinator(
            descriptor: descriptor,
            recoveryPointManager: manager,
            countsRepository: RecoveryPointCountsRepository(modelContainer: container),
            appVersion: "1.0.0",
            schemaVersion: 1,
            stableChangeMinimumInterval: interval
        )
    }

    private func date(_ timeIntervalSince1970: TimeInterval) -> Date {
        Date(timeIntervalSince1970: timeIntervalSince1970)
    }
}
