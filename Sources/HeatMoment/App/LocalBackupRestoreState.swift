import Foundation
import Observation

@MainActor
@Observable
final class LocalBackupRestoreState {
    var isPendingRestoreArmed: Bool
    var pendingContext: BackupPendingRestoreContext?

    init(
        isPendingRestoreArmed: Bool = false,
        pendingContext: BackupPendingRestoreContext? = nil
    ) {
        self.isPendingRestoreArmed = isPendingRestoreArmed
        self.pendingContext = pendingContext
    }

    func markPendingRestoreArmed(context: BackupPendingRestoreContext) {
        pendingContext = context
        isPendingRestoreArmed = true
    }

    func clearPendingRestore() {
        pendingContext = nil
        isPendingRestoreArmed = false
    }
}
