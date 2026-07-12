import Foundation

/// 本机自动恢复点能力边界，只覆盖列表、当前摘要和“准备恢复”。
///
/// 启动期真正消费 pending restore 的 boot gate 不属于这个协议；切换到 canonical
/// adapter 前，必须先把对应 storage runtime 的 boot restore gate 接入 App 启动路径。
protocol BackupRestoreServicing: Sendable {
    func listRecoveryPoints() async throws -> [BackupRecoveryPoint]
    func currentCounts() async throws -> BackupRecoveryCounts
    func prepareRestore(id: UUID) async throws -> BackupPendingRestoreContext
}

struct BackupRecoveryPoint: Identifiable, Sendable, Equatable {
    let id: UUID
    let createdAt: Date
    let reason: BackupRecoveryPointReason
    let status: BackupRecoveryPointStatus
    let schemaVersion: Int
    let appVersion: String
    let counts: BackupRecoveryCounts
}

struct BackupRecoveryCounts: Sendable, Equatable {
    let recordCount: Int
    let tagCount: Int
    let assetCount: Int
}

enum BackupRecoveryPointReason: Sendable, Equatable {
    case mutationSafety
    case restoreSafety
    case schemaMigration
    case stableChanges
}

enum BackupRecoveryPointStatus: Sendable, Equatable {
    case available
    case invalid
}

struct BackupPendingRestoreContext: Sendable, Equatable {
    let selectedRecoveryPointID: UUID
    let selectedCreatedAt: Date
    let restoreSafetyPointID: UUID?
    let restoreSafetyCreatedAt: Date?
}

enum BackupBootRestoreResult: Equatable {
    case none
    case restored(BackupPendingRestoreContext)
    case failed(BackupBootRestoreFailure)
}

struct BackupBootRestoreFailure: Error, Equatable, CustomStringConvertible {
    let underlyingDescription: String
    let context: BackupPendingRestoreContext?

    init(underlying: Error, context: BackupPendingRestoreContext? = nil) {
        underlyingDescription = String(describing: underlying)
        self.context = context
    }

    var description: String {
        "本地备份恢复失败：\(underlyingDescription)"
    }
}

struct CanonicalBackupRestoreService: BackupRestoreServicing {
    let coordinator: CanonicalRecoveryCoordinator

    func listRecoveryPoints() async throws -> [BackupRecoveryPoint] {
        let recoveryPoints = try await coordinator.listRecoveryPoints()
        return recoveryPoints.map(BackupRecoveryPoint.init(record:))
    }

    func currentCounts() async throws -> BackupRecoveryCounts {
        let counts = try await coordinator.currentCounts()
        return BackupRecoveryCounts(counts: counts)
    }

    func prepareRestore(id: UUID) async throws -> BackupPendingRestoreContext {
        let preparedRestore = try await coordinator.prepareRestore(id: id)
        return BackupPendingRestoreContext(preparedRestore: preparedRestore)
    }
}

extension BackupRecoveryPoint {
    init(record: CanonicalRecoveryPointRecord) {
        self.init(
            id: record.id,
            createdAt: record.createdAt,
            reason: BackupRecoveryPointReason(reason: record.reason),
            status: BackupRecoveryPointStatus(status: record.status),
            schemaVersion: record.schemaVersion,
            appVersion: record.appVersion,
            counts: BackupRecoveryCounts(counts: record.counts)
        )
    }
}

extension BackupRecoveryCounts {
    init(counts: CanonicalRecoveryPointCounts) {
        self.init(
            recordCount: counts.recordCount,
            tagCount: counts.tagCount,
            assetCount: counts.assetCount
        )
    }
}

extension BackupRecoveryPointReason {
    init(reason: CanonicalRecoveryPointReason) {
        switch reason {
        case .mutationSafety: self = .mutationSafety
        case .restoreSafety: self = .restoreSafety
        case .schemaMigration: self = .schemaMigration
        case .stableChanges: self = .stableChanges
        }
    }
}

extension BackupRecoveryPointStatus {
    init(status: CanonicalRecoveryPointStatus) {
        switch status {
        case .available: self = .available
        case .invalid: self = .invalid
        }
    }
}

extension BackupPendingRestoreContext {
    init(preparedRestore: CanonicalPreparedRestore) {
        self.init(
            selectedRecoveryPointID: preparedRestore.selectedRecoveryPoint.id,
            selectedCreatedAt: preparedRestore.selectedRecoveryPoint.createdAt,
            restoreSafetyPointID: preparedRestore.restoreSafetyRecoveryPoint.id,
            restoreSafetyCreatedAt: preparedRestore.restoreSafetyRecoveryPoint.createdAt
        )
    }

    init(context: CanonicalPendingRestoreContext) {
        self.init(
            selectedRecoveryPointID: context.selectedRecoveryPointID,
            selectedCreatedAt: context.selectedCreatedAt,
            restoreSafetyPointID: context.restoreSafetyRecoveryPoint?.id,
            restoreSafetyCreatedAt: context.restoreSafetyRecoveryPoint?.createdAt
        )
    }
}

extension BackupBootRestoreResult {
    init(result: CanonicalBootRestoreResult) {
        switch result {
        case .none:
            self = .none
        case let .restored(context):
            self = .restored(BackupPendingRestoreContext(context: context))
        case let .failed(failure):
            self = .failed(BackupBootRestoreFailure(failure: failure))
        }
    }
}

extension BackupBootRestoreFailure {
    init(failure: CanonicalBootRestoreFailure) {
        self.init(
            underlyingDescription: failure.underlyingDescription,
            context: failure.context.map(BackupPendingRestoreContext.init(context:))
        )
    }

    private init(
        underlyingDescription: String,
        context: BackupPendingRestoreContext?
    ) {
        self.underlyingDescription = underlyingDescription
        self.context = context
    }
}
