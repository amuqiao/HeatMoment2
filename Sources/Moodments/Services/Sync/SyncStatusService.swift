import Foundation
import Network
import Observation

/// iCloud 同步状态展示三态（见 `docs/design/09-icloud-sync.md` §9.2）。
enum SyncStatus: Sendable, Equatable {
    /// 已同步。
    case synced
    /// 同步中。
    case syncing
    /// 离线，将在联网后同步（含 CloudKit 未启用——见 `SyncStatusService.init(cloudKitEnabled:)`）。
    case offline

    var displayText: String {
        switch self {
        case .synced: LanguagePreference.localizedString("已同步")
        case .syncing: LanguagePreference.localizedString("同步中")
        case .offline: LanguagePreference.localizedString("离线，将在联网后同步")
        }
    }
}

/// 网络可达性判定的注入点（供单测替身，避免真实 `NWPathMonitor` 在单测环境下的不确定性，
/// 见 `SyncStatusServiceTests`）。
///
/// **异步（阶段7 review 修复）**：此前 `DefaultNetworkReachabilityChecker` 用
/// `DispatchSemaphore.wait(timeout:)` 同步阻塞等待 `NWPathMonitor` 回调，在 `@MainActor` 的
/// `SyncStatusService.refresh()` 内被同步调用时，会最长阻塞主线程 1 秒（打开设置页即卡顿）。
/// 改为 `async` 后，等待改为 `Task` 挂起（不占用任何线程），`refresh()` 的调用方 `await` 挂起期间
/// 主线程可继续处理其他事件，恢复后自动跳回 `@MainActor` 更新 `status`。
protocol NetworkReachabilityChecking: Sendable {
    func isReachable() async -> Bool
}

/// 基于 `NWPathMonitor` 单次快照的默认实现（生产路径）。
struct DefaultNetworkReachabilityChecker: NetworkReachabilityChecking {
    /// 单次查询的「已完成」标记：`NWPathMonitor.pathUpdateHandler` 固定在同一个私有串行队列
    /// 上顺序回调（不存在并发写），首次回调后立即 `cancel()` 停止后续回调，标记只用于防御
    /// `cancel()` 生效前紧随的重复回调导致 `continuation` 被 resume 两次（会触发运行时 crash）。
    /// `@unchecked Sendable`：无并发读写重叠，见上述串行队列前提。
    private final class ResumeGuard: @unchecked Sendable {
        var hasResumed = false
    }

    func isReachable() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let resumeGuard = ResumeGuard()
            monitor.pathUpdateHandler = { path in
                guard !resumeGuard.hasResumed else { return }
                resumeGuard.hasResumed = true
                continuation.resume(returning: path.status == .satisfied)
                monitor.cancel()
            }
            monitor.start(queue: DispatchQueue(label: "com.moodments.sync.reachability"))
        }
    }
}

/// 评估一次同步状态所需的全部输入（纯值类型，供 `SyncStatusService.evaluate(_:)` 单元测试
/// 不依赖真实网络/CloudKit，见 `SyncStatusServiceTests`）。
struct SyncStatusEvaluationInput: Sendable, Equatable {
    let cloudKitEnabled: Bool
    let isNetworkReachable: Bool
    let lastLocalWriteAt: Date?
    let now: Date
}

/// CloudKit 同步状态推导（见 09-icloud-sync.md §9.2）：SwiftData 目前未提供高层公开 API 直接
/// 暴露「同步中/已同步/失败」细粒度事件（`ModelContainer` 无法公开访问到底层
/// `NSPersistentCloudKitContainer`，文档已标注为开放问题），本类型按文档给出的**启发式退化
/// 方案**实现：以「最近一次本地写入 + 网络可达性」推断展示三态，而非依赖不稳定的事件粒度。
///
/// - CloudKit 未启用（生产容器回退本地，见 `ModelContainerConfig.makeProductionContainer()`）
///   恒 `.offline`——本就没有同步这回事。
/// - CloudKit 已启用：网络不可达 → `.offline`；网络可达且刚发生过本地写入（短时间窗口内）→
///   `.syncing`（近似展示「正在上传」的观感）；否则 → `.synced`。
@MainActor
@Observable
final class SyncStatusService {
    /// 「同步中」判定窗口：本地写入后短时间内展示「同步中」（纯启发式近似，非真实进度）。
    /// `nonisolated`：纯常量，供 `evaluate(_:)` 与单测在非隔离上下文直接读取。
    nonisolated static let syncingWindow: TimeInterval = 5

    private(set) var status: SyncStatus
    let cloudKitEnabled: Bool

    private let reachabilityChecker: NetworkReachabilityChecking
    private var lastLocalWriteAt: Date?

    init(
        cloudKitEnabled: Bool,
        reachabilityChecker: NetworkReachabilityChecking = DefaultNetworkReachabilityChecker()
    ) {
        self.cloudKitEnabled = cloudKitEnabled
        self.reachabilityChecker = reachabilityChecker
        self.status = cloudKitEnabled ? .synced : .offline
    }

    /// 供写入路径（仓库层完成一次保存后）通知「刚发生过一次本地写入」，驱动短暂的
    /// 「同步中」展示；未接入调用方时 `status` 只在 `refresh()` 被显式调用时才更新。
    /// 内部以 `Task` 触发异步 `refresh(now:)`（fire-and-forget，不阻塞调用方）。
    func noteLocalWrite(at date: Date = .now) {
        lastLocalWriteAt = date
        Task { await refresh(now: date) }
    }

    /// 重新计算当前状态（如设置页 iCloud 行每次展示时调用）：`async`（阶段7 review 修复，见
    /// `NetworkReachabilityChecking` 类型头部说明）——挂起等待网络可达性查询期间不阻塞主线程，
    /// 恢复后仍在 `@MainActor` 上更新 `status`。
    func refresh(now: Date = .now) async {
        let isNetworkReachable = await reachabilityChecker.isReachable()
        status = Self.evaluate(SyncStatusEvaluationInput(
            cloudKitEnabled: cloudKitEnabled,
            isNetworkReachable: isNetworkReachable,
            lastLocalWriteAt: lastLocalWriteAt,
            now: now
        ))
    }

    /// 纯逻辑推导（见类型头部说明），供单测直接注入输入验证，不依赖真实网络/CloudKit。
    /// `nonisolated`：不触碰任何实例状态，可在非 `@MainActor` 上下文（如单测）同步调用。
    nonisolated static func evaluate(_ input: SyncStatusEvaluationInput) -> SyncStatus {
        guard input.cloudKitEnabled else { return .offline }
        guard input.isNetworkReachable else { return .offline }
        if let lastWrite = input.lastLocalWriteAt, input.now.timeIntervalSince(lastWrite) < syncingWindow {
            return .syncing
        }
        return .synced
    }
}
