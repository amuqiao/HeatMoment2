import Foundation
import Observation

@MainActor
@Observable
final class LocalBackupRestoreState {
    var isPendingRestoreArmed: Bool
    var pendingContext: LocalBackupPendingRestoreContext?

    init(
        isPendingRestoreArmed: Bool = false,
        pendingContext: LocalBackupPendingRestoreContext? = nil
    ) {
        self.isPendingRestoreArmed = isPendingRestoreArmed
        self.pendingContext = pendingContext
    }

    func markPendingRestoreArmed(context: LocalBackupPendingRestoreContext) {
        pendingContext = context
        isPendingRestoreArmed = true
    }

    func clearPendingRestore() {
        pendingContext = nil
        isPendingRestoreArmed = false
    }
}
