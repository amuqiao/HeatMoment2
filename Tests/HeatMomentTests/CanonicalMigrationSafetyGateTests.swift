import XCTest
@testable import HeatMoment

final class CanonicalMigrationSafetyGateTests: XCTestCase {}

extension CanonicalMigrationSafetyGateTests {
    func testCreatesSchemaMigrationRecoveryPointAndValidatesIt() async throws {
        let fixture = try makeFixture()
        let coordinator = CanonicalRecoveryCoordinator(
            runtime: fixture.runtime,
            appVersion: "1.0.8"
        )
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000005101")

        _ = try await fixture.runtime.repository.createMoment(
            title: "迁移前内容",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .normal
        )

        let recoveryPoint = try await CanonicalMigrationSafetyGate.createRequiredRecoveryPoint(
            using: coordinator,
            id: recoveryPointID,
            createdAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(recoveryPoint.id, recoveryPointID)
        XCTAssertEqual(recoveryPoint.reason, .schemaMigration)
        XCTAssertEqual(recoveryPoint.status, .available)
        XCTAssertEqual(recoveryPoint.counts.recordCount, 1)
        let listedIDs = try await coordinator.listRecoveryPoints().map(\.id)
        XCTAssertEqual(listedIDs, [recoveryPointID])
    }

    func testCreateFailureAbortsBeforeValidation() async throws {
        var didValidate = false

        do {
            _ = try await CanonicalMigrationSafetyGate.createRequiredRecoveryPoint(
                createRecoveryPoint: { _, _ in
                    throw InjectedCreateError.createFailed
                },
                validateRecoveryPoint: { id in
                    didValidate = true
                    return self.recoveryPointRecord(id: id)
                }
            )
            XCTFail("迁移前恢复点创建失败时不应继续")
        } catch {
            XCTAssertEqual(error as? InjectedCreateError, .createFailed)
            XCTAssertFalse(didValidate)
        }
    }

    func testValidationFailureAbortsMigrationSafetyPoint() async throws {
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000005201")

        do {
            _ = try await CanonicalMigrationSafetyGate.createRequiredRecoveryPoint(
                id: recoveryPointID,
                createRecoveryPoint: { id, _ in
                    self.recoveryPointRecord(id: id)
                },
                validateRecoveryPoint: { _ in
                    throw InjectedValidationError.validationFailed
                }
            )
            XCTFail("迁移前恢复点校验失败时不应继续")
        } catch {
            XCTAssertEqual(error as? InjectedValidationError, .validationFailed)
        }
    }

    func testInvalidValidatedRecoveryPointAbortsMigrationSafetyPoint() async throws {
        let recoveryPointID = uuid("00000000-0000-0000-0000-000000005301")

        do {
            _ = try await CanonicalMigrationSafetyGate.createRequiredRecoveryPoint(
                id: recoveryPointID,
                createRecoveryPoint: { id, _ in
                    self.recoveryPointRecord(id: id)
                },
                validateRecoveryPoint: { id in
                    self.recoveryPointRecord(id: id, status: .invalid)
                }
            )
            XCTFail("迁移前恢复点不可用时不应继续")
        } catch {
            XCTAssertEqual(
                error as? CanonicalMigrationSafetyGateError,
                .recoveryPointUnavailable(recoveryPointID)
            )
        }
    }

    func testSafetyPointUsesRecoveryPointRetention() async throws {
        let fixture = try makeFixture()
        let coordinator = CanonicalRecoveryCoordinator(
            runtime: fixture.runtime,
            appVersion: "1.0.8"
        )
        let oldestID = uuid("00000000-0000-0000-0000-000000005401")
        let secondID = uuid("00000000-0000-0000-0000-000000005402")
        let thirdID = uuid("00000000-0000-0000-0000-000000005403")
        let safetyID = uuid("00000000-0000-0000-0000-000000005404")

        _ = try await coordinator.createRecoveryPoint(
            id: oldestID,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        _ = try await coordinator.createRecoveryPoint(
            id: secondID,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        _ = try await coordinator.createRecoveryPoint(
            id: thirdID,
            createdAt: Date(timeIntervalSince1970: 300)
        )

        _ = try await CanonicalMigrationSafetyGate.createRequiredRecoveryPoint(
            using: coordinator,
            id: safetyID,
            createdAt: Date(timeIntervalSince1970: 400)
        )

        let listedIDs = try await coordinator.listRecoveryPoints().map(\.id)
        XCTAssertEqual(listedIDs, [safetyID, thirdID, secondID])
        XCTAssertFalse(listedIDs.contains(oldestID))
    }
}

private extension CanonicalMigrationSafetyGateTests {
    enum InjectedCreateError: Error, Equatable {
        case createFailed
    }

    enum InjectedValidationError: Error, Equatable {
        case validationFailed
    }

    struct Fixture {
        let rootDirectory: URL
        let runtime: CanonicalLibraryRuntime
    }

    func makeFixture() throws -> Fixture {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CanonicalMigrationSafetyGateTests-\(UUID().uuidString)",
                isDirectory: true
            )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        let runtime = try CanonicalLibraryRuntime(
            descriptor: CanonicalStoreDescriptor(rootDirectory: rootDirectory)
        )
        return Fixture(rootDirectory: rootDirectory, runtime: runtime)
    }

    func recoveryPointRecord(
        id: UUID,
        status: CanonicalRecoveryPointStatus = .available
    ) -> CanonicalRecoveryPointRecord {
        CanonicalRecoveryPointRecord(
            id: id,
            createdAt: Date(timeIntervalSince1970: 100),
            reason: .schemaMigration,
            status: status,
            schemaVersion: CanonicalStore.currentSchemaVersion,
            appVersion: "1.0.8",
            sourceLibraryID: uuid("00000000-0000-0000-0000-000000005999"),
            sqliteSnapshot: CanonicalRecoveryPointSnapshot(
                relativePath: "RecoveryPoints/\(id.uuidString)/Library.sqlite",
                byteCount: 1,
                sha256: String(repeating: "a", count: 64)
            ),
            counts: CanonicalRecoveryPointCounts(recordCount: 0, usedTagCount: 0, assetCount: 0)
        )
    }

    func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
