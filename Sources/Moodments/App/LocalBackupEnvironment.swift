import SwiftUI

private struct LocalBackupCoordinatorEnvironmentKey: EnvironmentKey {
    static let defaultValue: LocalBackupCoordinator? = nil
}

extension EnvironmentValues {
    var localBackupCoordinator: LocalBackupCoordinator? {
        get { self[LocalBackupCoordinatorEnvironmentKey.self] }
        set { self[LocalBackupCoordinatorEnvironmentKey.self] = newValue }
    }
}

@MainActor
enum LocalBackupWriteRecorder {
    static func recordStableChanges(
        using coordinator: LocalBackupCoordinator?,
        errorPresenter: ErrorPresenter
    ) {
        guard let coordinator else { return }
        Task { @MainActor in
            do {
                try await coordinator.createStableChangesRecoveryPointIfNeeded()
            } catch {
                errorPresenter.report(message: "创建本地备份失败，请稍后重试。", underlying: error)
            }
        }
    }

    static func createMutationSafetyPoint(
        using coordinator: LocalBackupCoordinator?
    ) async throws {
        guard let coordinator else { return }
        try await coordinator.createMutationSafetyRecoveryPoint()
    }
}
