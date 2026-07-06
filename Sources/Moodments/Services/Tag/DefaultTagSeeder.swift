import Foundation

/// 首启默认标签预置（见 `docs/design/07-data-persistence.md` §4）：首次启动、`Tag` 表为空时
/// 预置「工作 / 生活 / 健康」三个默认标签（已裁决）。注意副作用：免费标签上限为 3，预置 3 个
/// 即占满免费额度——新用户要自建标签需先删除已有标签或升级 Pro，此为已知且可接受的取舍。
/// 非首次（`Tag` 表非空）不重复预置。本类型不区分生产/UI 测试场景，二者都需要这份默认数据
/// （UI 测试的标签额度拦截验收正是基于「默认预置已占满额度」这一口径，见阶段 3 计划）。
///
/// 写入统一经后台 `TagRepository`（`@ModelActor`），与「标签增删改走 ModelActor」的分层契约
/// 一致（见 `docs/design/08-architecture.md` §5），不在主上下文直接写库。
///
/// **首同步去重**（阶段7计划决策3、`docs/design/09-icloud-sync.md`）：CloudKit 已启用时，
/// 若冷启动瞬间本地 `Tag` 表恰好还没来得及接收另一台设备早已同步上去的默认标签，「表为空」
/// 的旧判定会导致两台设备各自预置一遍、合并后出现重复标签。改为**按名去重**（应用层查重，
/// CloudKit 不支持 `.unique`，见 07 §2）——三个默认名逐一检查，缺哪个补哪个，而非「非空即
/// 跳过整批」；并在检查前**等待一次首次同步信号或短超时**（`firstSyncGraceTimeout`），
/// 给刚启动的 CloudKit 同步一个窗口期把已有数据拉下来。CloudKit 未启用（本地容器，含全部
/// 单测/UI 测试路径）时跳过等待，行为与阶段 1–6 完全等价（表空即预置，无额外延迟）。
enum DefaultTagSeeder {
    static let defaultNames = ["工作", "生活", "健康"]

    /// 首启预置前的最长等待时长（仅 CloudKit 已启用时生效，见类型头部「短超时兜底」）。
    static let firstSyncGraceTimeout: Duration = .seconds(2)

    /// - Parameters:
    ///   - cloudKitEnabled: 当前容器是否启用了 CloudKit 同步（见
    ///     `ModelContainerConfig.makeProductionContainer()`）；默认 `false`（本地容器/单测路径，
    ///     行为与阶段 1–6 完全等价，不引入等待）。
    ///   - firstImportSignal: 供未来接入真实 CloudKit 首次 import 完成通知使用的注入点；
    ///     `nil`（默认）时只依赖 `firstSyncGraceTimeout` 短超时兜底（见类型头部说明——真实
    ///     CloudKit import 事件粒度是 `09-icloud-sync.md` §9.2 标注的开放问题，本类型不强依赖它）。
    /// - Throws: 底层仓库存取失败时抛出，不做静默兜底（见 CLAUDE.md「不擅自添加兜底策略」）。
    static func seedIfNeeded(
        using repository: TagRepository,
        cloudKitEnabled: Bool = false,
        firstImportSignal: (@Sendable () async -> Void)? = nil
    ) async throws {
        if cloudKitEnabled {
            await waitForFirstSyncOrTimeout(firstImportSignal: firstImportSignal)
        }
        for name in defaultNames where try await repository.findTag(named: name) == nil {
            try await repository.createTag(name: name)
        }
    }

    private static func waitForFirstSyncOrTimeout(firstImportSignal: (@Sendable () async -> Void)?) async {
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
