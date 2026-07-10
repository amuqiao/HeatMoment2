import SwiftData
import SwiftUI

/// 根视图：装载时间轴首页，并把 `AppRouter` 的跨页导航意图呈现为对应浮层——
/// 任务卡片栈用 `.sheet(item:)`（page sheet，多层叠加的下沉由系统负责，见 14 ADR-003）、
/// 沉浸全屏用 `.fullScreenCover(item:)`。年度热力图、筛选、日期/时间等首页/字段局部层
/// 不在此处——由触发处局部状态就近驱动、不进 Router。
///
/// **`TimelineModel` 上提**（阶段5必要重构，见该类型头部注释）：在此创建并通过 `.environment()`
/// 注入整棵树（含 `TimelineHomeView` 与 `YearHeatmapView`），使时间轴与热力图
/// 共享同一份「定位/筛选」状态，而不是两份互不相干的拷贝。
struct RootView: View {
    let localBackupCoordinator: LocalBackupCoordinator?

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(SyncStatusService.self) private var syncStatusService
    @State private var timelineModel = TimelineModel()

    init(localBackupCoordinator: LocalBackupCoordinator? = nil) {
        self.localBackupCoordinator = localBackupCoordinator
    }

    var body: some View {
        @Bindable var router = router
        TimelineHomeView()
            .sheet(item: $router.rootSheet) { sheet in
                switch sheet {
                case let .preview(id): MomentPreviewView(momentID: id)
                case let .editor(mode):
                    MomentEditorView(
                        mode: mode, modelContainer: modelContext.container,
                        subscriptionService: subscriptionService
                    )
                case .settings: SettingsSheetView()
                case let .paywall(trigger): ProPaywallView(trigger: trigger)
                }
            }
            // 预留路由入口（见 AppRouter.FullCover 说明）：当前无写入方，图片查看器由预览局部呈现。
            .fullScreenCover(item: $router.fullScreenCover) { cover in
                switch cover {
                case let .imageViewer(momentID, index):
                    ImageViewerView(momentID: momentID, startIndex: index)
                }
            }
            .environment(timelineModel)
            .userFacingErrorAlert(errorPresenter)
            .task {
                var canCreateLocalBackup = true
                // 首启默认标签预置（见 07-data-persistence.md §4）：无条件调用（生产与 UI 测试
                // 均需要），是否真正执行预置由 `DefaultTagSeeder` 内部的持久化「首启已完成」标记
                // 判定（而非 `Tag` 表是否为空——用户删除默认标签后表可能变空/不完整，若仍按
                // 表内容判定会导致已删除的默认标签复活，见该类型头部 review 修复说明）。经后台
                // TagRepository 写入（08 §5 分层契约）。`cloudKitEnabled` 决定首启窗口内是否需要
                // 「首同步去重」的等待（阶段7计划决策3）——本地/单测/UI 测试路径恒 `false`，行为
                // 与阶段 1–6 完全等价、零额外延迟；非首启（flag 已置位）任何路径下都零延迟。
                do {
                    #if DEBUG
                        let shouldSeedDefaultTags = !UITestSupport.wantsSkipDefaultTags
                    #else
                        let shouldSeedDefaultTags = true
                    #endif
                    if shouldSeedDefaultTags {
                        let tagRepository = TagRepository(modelContainer: modelContext.container)
                        try await DefaultTagSeeder.seedIfNeeded(
                            using: tagRepository, cloudKitEnabled: syncStatusService.cloudKitEnabled
                        )
                    }
                } catch {
                    canCreateLocalBackup = false
                    errorPresenter.report(message: "初始化默认标签失败，请重启应用重试。", underlying: error)
                }
                if canCreateLocalBackup, let localBackupCoordinator {
                    do {
                        try await localBackupCoordinator.createLaunchRecoveryPoint()
                    } catch {
                        errorPresenter.report(message: "创建本地备份失败，请稍后重试。", underlying: error)
                    }
                }
                #if DEBUG
                    UITestSupport.seedIfRequested(modelContext)
                    UITestSupport.seedImageMomentIfRequested(modelContext)
                    UITestSupport.seedMomentQuotaIfRequested(modelContext)
                #endif
            }
    }
}
