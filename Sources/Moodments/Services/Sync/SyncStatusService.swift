import Foundation
import Network
import Observation

/// iCloud 同步状态展示三态（见 `docs/plans/implementation-plan.md` §9.2）。
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
    /// 单次查询的「已完成」标记：`NWPathMonitor.pathUpdateHandler` 与下方超时兜底任务可能各自
    /// 尝试 resume 同一个 `continuation`（正常回调 vs. 超时兜底二选一，谁先到谁生效），标记
    /// 用一把锁防御二者的竞态重复 resume（会触发运行时 crash）——`pathUpdateHandler` 自身固定
    /// 在同一个私有串行队列上顺序回调不存在并发写，但超时兜底运行在 `Task` 的另一执行上下文，
    /// 与该串行队列之间不再有天然互斥，故改用锁而非早先纯标记位。
    private final class ResumeGuard: @unchecked Sendable {
        private let lock = NSLock()
        private var hasResumed = false

        /// 原子地「若尚未 resume 则占用」；返回 `true` 表示调用方拿到了唯一一次 resume 权限。
        func tryClaim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !hasResumed else { return false }
            hasResumed = true
            return true
        }
    }

    /// 查询超时兜底：`NWPathMonitor` 极端情况下（如系统网络子系统异常）可能首次回调始终不来，
    /// `withCheckedContinuation` 会永久挂起、`continuation` 永久不被 resume（资源泄漏，调用方
    /// `await` 也会随之永久挂起）。这不是业务失败降级，而是**操作超时的资源安全兜底**
    /// （见 CLAUDE.md「不擅自添加兜底策略」——本超时只负责让 continuation 一定被 resume 一次，
    /// 不改变「查不到就当作不可达」之外的任何业务判断）：超时后按「不可达」处理（保守值，驱动
    /// `.offline` 展示，不会误报「已同步」），并 `cancel()` monitor 停止其后续回调。
    private static let queryTimeout: Duration = .seconds(2)

    func isReachable() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let resumeGuard = ResumeGuard()

            monitor.pathUpdateHandler = { path in
                guard resumeGuard.tryClaim() else { return }
                continuation.resume(returning: path.status == .satisfied)
                monitor.cancel()
            }
            monitor.start(queue: DispatchQueue(label: "com.moodments.sync.reachability"))

            Task {
                try? await Task.sleep(for: Self.queryTimeout)
                guard resumeGuard.tryClaim() else { return }
                continuation.resume(returning: false)
                monitor.cancel()
            }
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

/// iCloud 同步状态推导（见 docs/plans/implementation-plan.md §9.2）：当前生产数据权威是 canonical local store，
/// 尚未接入真实 iCloud 同步事件，因此本类型仍按文档给出的**启发式退化方案**实现：以「当前设备
/// 具备 iCloud 能力 + 最近一次本地写入 + 网络可达性」推断展示三态，而非表达真实上传/下载进度。
///
/// - iCloud 能力不可用时恒 `.offline`——本就没有同步这回事。
/// - iCloud 能力可用：网络不可达 → `.offline`；网络可达且刚发生过本地写入（短时间窗口内）→
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
        status = Self.evaluate(
            SyncStatusEvaluationInput(
                cloudKitEnabled: cloudKitEnabled,
                isNetworkReachable: isNetworkReachable,
                lastLocalWriteAt: lastLocalWriteAt,
                now: now
            )
        )
    }

    /// 纯逻辑推导（见类型头部说明），供单测直接注入输入验证，不依赖真实网络/CloudKit。
    /// `nonisolated`：不触碰任何实例状态，可在非 `@MainActor` 上下文（如单测）同步调用。
    nonisolated static func evaluate(_ input: SyncStatusEvaluationInput) -> SyncStatus {
        guard input.cloudKitEnabled else { return .offline }
        guard input.isNetworkReachable else { return .offline }
        if let lastWrite = input.lastLocalWriteAt,
           input.now.timeIntervalSince(lastWrite) < syncingWindow {
            return .syncing
        }
        return .synced
    }
}
