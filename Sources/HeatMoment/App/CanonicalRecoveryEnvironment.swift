import SwiftUI

private struct CanonicalRecoveryCoordinatorEnvironmentKey: EnvironmentKey {
    static let defaultValue: CanonicalRecoveryCoordinator? = nil
}

extension EnvironmentValues {
    var canonicalRecoveryCoordinator: CanonicalRecoveryCoordinator? {
        get { self[CanonicalRecoveryCoordinatorEnvironmentKey.self] }
        set { self[CanonicalRecoveryCoordinatorEnvironmentKey.self] = newValue }
    }
}

@MainActor
enum CanonicalRecoveryWriteRecorder {
    static func recordStableChanges(
        using coordinator: CanonicalRecoveryCoordinator?,
        errorPresenter: ErrorPresenter
    ) {
        guard let coordinator else { return }
        Task { @MainActor in
            do {
                try await coordinator.createStableChangesRecoveryPointIfNeeded()
            } catch {
                errorPresenter.report(message: "创建本机安全点失败，请稍后重试。", underlying: error)
            }
        }
    }

    static func createMutationSafetyPoint(
        using coordinator: CanonicalRecoveryCoordinator?
    ) async throws {
        guard let coordinator else { return }
        try await coordinator.createMutationSafetyRecoveryPoint()
    }
}
