import Foundation

/// 首启默认标签预置（见 `docs/current/local-data-architecture.md` §4）：**仅在真正首次启动**
/// （见下方 `hasCompletedFirstSeedKey` 持久标记）预置「工作 / 生活 / 健康」三个默认标签
/// （已裁决）。注意副作用：免费标签上限为 3，预置 3 个即占满免费额度——新用户要自建标签需先
/// 删除已有标签或升级 Pro，此为已知且可接受的取舍。本类型不区分生产/UI 测试场景，二者都需要
/// 这份默认数据（UI 测试的标签额度拦截验收正是基于「默认预置已占满额度」这一口径，见阶段 3
/// 计划；UI 测试每次运行需要「重新首启」的语义，由 `UITestSupport.resetDefaultTagSeedFlagIfUITestRun()`
/// 在每次冷启动 `init()` 内清掉持久标记来提供，与 `resetLanguagePreferenceIfUITestRun()` 同一模式）。
///
/// **不能用「`Tag` 表是否为空」判定首启**（阶段7 review 修复，见 code review）：`Tag` 是硬删除
/// （非软删除生命周期对象），用户删掉全部/部分默认标签后表会变空或不完整，若仍按「表空即预置」
/// 的旧口径，下次冷启动会把已删除的默认标签复活——不仅是体验回归，更会让非 Pro 用户被动持有
/// 超过免费上限（3）的标签数，绕过 `QuotaService` 判定。因此改用**独立于表内容的持久标记**
/// （`UserDefaults` 一次性 flag）：只在该标记未置位的「真正首启」窗口执行一次预置，预置成功后
/// 立即置位；此后不论表内容如何变化（含用户主动删除默认标签），永不再复活。
///
/// 写入统一经 canonical repository，默认标签不绕开资料库写入边界。
///
/// **首同步去重**（阶段7计划决策3、`docs/plans/implementation-plan.md`）：CloudKit 已启用时，
/// 若冷启动瞬间本地 `Tag` 表恰好还没来得及接收另一台设备早已同步上去的默认标签，直接按名创建
/// 会与稍后同步下来的数据产生重复。改为**按名去重**（应用层查重，CloudKit 不支持 `.unique`，
/// 见 docs/current/local-data-architecture.md §2）——三个默认名逐一检查，缺哪个补哪个；并在检查前**等待一次首次同步信号或短超时**
/// （`firstSyncGraceTimeout`），给刚启动的 CloudKit 同步一个窗口期把已有数据拉下来。这一等待
/// 与去重**只发生在首启窗口内**（已置位后的后续每次启动直接短路返回，不再有等待、不再有
/// 任何 canonical repository 查询）；CloudKit 未启用（本地容器，含全部单测/UI 测试路径）时同样跳过
/// 等待，行为与阶段 1–6 完全等价（首启即预置，无额外延迟）。
enum DefaultTagSeeder {
    static let defaultNames = ["工作", "生活", "健康"]

    /// 首启预置前的最长等待时长（仅 CloudKit 已启用时生效，见类型头部「短超时兜底」）。
    static let firstSyncGraceTimeout: Duration = .seconds(2)

    /// 「首启默认标签预置已完成」持久标记的 `UserDefaults` key（见类型头部说明）。
    /// UI 测试场景下由 `UITestSupport.resetDefaultTagSeedFlagIfUITestRun()` 在每次冷启动清掉，
    /// 单元测试场景下调用方注入隔离的 `UserDefaults` suite name（见 `DefaultTagSeederTests`），
    /// 二者都不会污染真实用户的 `UserDefaults.standard`。
    static let hasCompletedFirstSeedKey = "com.moodments.defaultTagSeeder.hasCompletedFirstSeed"

    /// - Parameters:
    ///   - cloudKitEnabled: 调用方是否已确认当前路径具备 CloudKit/iCloud 同步能力；默认 `false`
    ///     （本地/单测路径，行为与阶段 1–6 完全等价，不引入等待）。
    ///   - firstImportSignal: 供未来接入真实 CloudKit 首次 import 完成通知使用的注入点；
    ///     `nil`（默认）时只依赖 `firstSyncGraceTimeout` 短超时兜底（见类型头部说明——真实
    ///     CloudKit import 事件粒度是 `docs/plans/implementation-plan.md` §9.2 标注的开放问题，本类型不强依赖它）。
    ///   - userDefaultsSuiteName: 持久标记所在的 `UserDefaults` suite；`nil` 表示 `.standard`（生产路径）。
    /// - Throws: 底层仓库存取失败时抛出，不做静默兜底（见 CLAUDE.md「不擅自添加兜底策略」）。
    @discardableResult
    static func seedIfNeeded(
        using repository: CanonicalLibraryRepository,
        cloudKitEnabled: Bool = false,
        firstImportSignal: (@Sendable () async -> Void)? = nil,
        userDefaultsSuiteName: String? = nil
    ) async throws -> Bool {
        guard !hasCompletedFirstSeed(userDefaultsSuiteName: userDefaultsSuiteName) else {
            return false
        }
        if cloudKitEnabled {
            await waitForFirstSyncOrTimeout(firstImportSignal: firstImportSignal)
        }
        var didWrite = false
        for name in defaultNames where try await repository.findTag(named: name) == nil {
            _ = try await repository.createOrReuseTag(name: name)
            didWrite = true
        }
        markCompletedFirstSeed(userDefaultsSuiteName: userDefaultsSuiteName)
        return didWrite
    }

    private static func hasCompletedFirstSeed(userDefaultsSuiteName: String?) -> Bool {
        defaults(userDefaultsSuiteName: userDefaultsSuiteName)
            .bool(forKey: hasCompletedFirstSeedKey)
    }

    private static func markCompletedFirstSeed(userDefaultsSuiteName: String?) {
        defaults(userDefaultsSuiteName: userDefaultsSuiteName)
            .set(true, forKey: hasCompletedFirstSeedKey)
    }

    private static func defaults(userDefaultsSuiteName: String?) -> UserDefaults {
        guard let userDefaultsSuiteName else { return .standard }
        return UserDefaults(suiteName: userDefaultsSuiteName) ?? .standard
    }

    private static func waitForFirstSyncOrTimeout(
        firstImportSignal: (@Sendable () async -> Void)?
    ) async {
        guard let firstImportSignal else {
            try? await Task.sleep(for: firstSyncGraceTimeout)
            return
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await firstImportSignal() }
            group.addTask { try? await Task.sleep(for: firstSyncGraceTimeout) }
            await group.next()
            group.cancelAll()
        }
    }
}
