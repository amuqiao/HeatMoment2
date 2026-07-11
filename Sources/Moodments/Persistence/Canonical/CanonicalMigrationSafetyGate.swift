import Foundation

enum CanonicalMigrationSafetyGateError: Error, Equatable {
    case recoveryPointUnavailable(UUID)
    case validatedDifferentRecoveryPoint(expected: UUID, actual: UUID)
}

enum CanonicalMigrationSafetyGate {
    @discardableResult
    static func createRequiredRecoveryPoint(
        using coordinator: CanonicalRecoveryCoordinator,
        id: UUID = UUID(),
        createdAt: Date = .now
    ) async throws -> CanonicalRecoveryPointRecord {
        try await createRequiredRecoveryPoint(
            id: id,
            createdAt: createdAt,
            createRecoveryPoint: { id, createdAt in
                try await coordinator.createRecoveryPoint(
                    reason: .schemaMigration,
                    id: id,
                    createdAt: createdAt
                )
            },
            validateRecoveryPoint: { id in
                try await coordinator.validateRecoveryPoint(id: id)
            }
        )
    }

    @discardableResult
    static func createRequiredRecoveryPoint(
        id: UUID = UUID(),
        createdAt: Date = .now,
        createRecoveryPoint:
            (UUID, Date) async throws -> CanonicalRecoveryPointRecord,
        validateRecoveryPoint:
            (UUID) async throws -> CanonicalRecoveryPointRecord
    ) async throws -> CanonicalRecoveryPointRecord {
        let created = try await createRecoveryPoint(id, createdAt)
        let validated = try await validateRecoveryPoint(created.id)
        guard validated.id == created.id else {
            throw CanonicalMigrationSafetyGateError.validatedDifferentRecoveryPoint(
                expected: created.id,
                actual: validated.id
            )
        }
        guard validated.status == .available else {
            throw CanonicalMigrationSafetyGateError.recoveryPointUnavailable(validated.id)
        }
        return validated
    }
}
