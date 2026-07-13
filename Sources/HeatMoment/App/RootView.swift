import SwiftUI

/// App shell：装载可替换的 HeatMoment 首页，并把 `AppRouter` 的跨页导航意图呈现为全局浮层。
///
/// 根级任务卡片栈使用 `.sheet(item:)`。年度热力图、筛选、日期/时间、图片查看器等
/// 就地或二层浮层由触发 feature 局部状态驱动，不进入 Router。
///
/// **`TimelineModel` 上提**（阶段5必要重构，见该类型头部注释）：在此创建并通过 `.environment()`
/// 注入整棵树（含 `TimelineHomeView` 与 `YearHeatmapView`），使时间轴与热力图
/// 共享同一份「定位/筛选」状态，而不是两份互不相干的拷贝。
struct RootView: View {
    let canonicalRecoveryCoordinator: CanonicalRecoveryCoordinator?
    let backupRestoreService: (any BackupRestoreServicing)?
    let exportService: any ExportServicing
    let launchRestoreResult: BackupBootRestoreResult

    @Environment(AppRouter.self) private var router
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(CanonicalLibraryService.self) private var canonicalService
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(SyncStatusService.self) private var syncStatusService
    @State private var timelineModel = TimelineModel()
    @State private var didHandleLaunchRestoreResult = false
    @State private var isReadyForInteraction = false
    @State private var showsLaunchRestoreSuccess = false
    @State private var launchRestoreSuccessMessage = ""

    init(
        canonicalRecoveryCoordinator: CanonicalRecoveryCoordinator? = nil,
        backupRestoreService: (any BackupRestoreServicing)? = nil,
        exportService: any ExportServicing,
        launchRestoreResult: BackupBootRestoreResult = .none
    ) {
        self.canonicalRecoveryCoordinator = canonicalRecoveryCoordinator
        self.backupRestoreService = backupRestoreService
        self.exportService = exportService
        self.launchRestoreResult = launchRestoreResult
    }

    var body: some View {
        @Bindable var router = router
        rootScene
        .sheet(item: $router.rootSheet) { sheet in
            rootTaskSheet(sheet)
        }
        .environment(timelineModel)
        .alert("本地备份恢复完成", isPresented: $showsLaunchRestoreSuccess) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(launchRestoreSuccessMessage)
        }
        .userFacingErrorAlert(errorPresenter)
        .task {
            await prepareForInteraction()
        }
    }

    // MARK: - Root Scene

    @ViewBuilder
    private var rootScene: some View {
        if canonicalService.isPrepared && isReadyForInteraction {
            heatmomentHomeScene
        } else {
            loadingScene
        }
    }

    /// HeatMoment business home. Future small apps can replace this scene without taking over app-level
    /// privacy lock, restore overlays, language, theme, StoreKit, or global sheet policy.
    private var heatmomentHomeScene: some View {
        TimelineHomeView()
    }

    private var loadingScene: some View {
        ZStack {
            HomeSceneBackgroundView().ignoresSafeArea()
            ProgressView()
        }
    }

    // MARK: - Presentation Policy

    @ViewBuilder
    private func rootTaskSheet(_ sheet: RootSheet) -> some View {
        switch sheet {
        case let .preview(id):
            MomentPreviewView(momentID: id)
        case let .editor(mode):
            MomentEditorView(
                mode: mode,
                canonicalService: canonicalService,
                subscriptionService: subscriptionService
            )
        case .settings:
            SettingsSheetView(
                backupRestoreService: backupRestoreService,
                exportService: exportService
            )
        case let .paywall(trigger):
            ProPaywallView(trigger: trigger)
        }
    }

    // MARK: - App Readiness

    private func prepareForInteraction() async {
        handleLaunchRestoreResultIfNeeded()

        do {
            try await canonicalService.prepareIfNeeded()
            #if DEBUG
                await UITestSupport.seedIfRequested(canonicalService)
                await UITestSupport.seedImageMomentIfRequested(canonicalService)
                await UITestSupport.seedMomentQuotaIfRequested(canonicalService)
                await UITestSupport.seedCanonicalRecoveryPointIfRequested(
                    canonicalService,
                    coordinator: canonicalRecoveryCoordinator
                )
            #endif
        } catch {
            errorPresenter.report(
                message: "初始化本地资料库失败，请重启应用重试。",
                underlying: error
            )
            return
        }

        do {
            try await seedDefaultTagsIfNeeded()
        } catch {
            errorPresenter.report(message: "初始化默认标签失败，请重启应用重试。", underlying: error)
            return
        }

        isReadyForInteraction = true
    }

    private func handleLaunchRestoreResultIfNeeded() {
        guard !didHandleLaunchRestoreResult else { return }
        didHandleLaunchRestoreResult = true

        switch launchRestoreResult {
        case .none:
            break
        case let .restored(context):
            launchRestoreSuccessMessage = Self.launchRestoreSuccessMessage(context: context)
            showsLaunchRestoreSuccess = true
        case let .failed(failure):
            errorPresenter.report(
                message: "本地备份恢复失败，当前数据未被替换。",
                underlying: failure
            )
        }
    }

    private func seedDefaultTagsIfNeeded() async throws {
        // 首启默认标签预置：无条件调用（生产与 UI 测试均需要），是否真正执行预置由
        // `DefaultTagSeeder` 内部的持久化「首启已完成」标记判定，而非标签表是否为空。
        #if DEBUG
            let shouldSeedDefaultTags = !UITestSupport.wantsSkipDefaultTags
        #else
            let shouldSeedDefaultTags = true
        #endif
        if shouldSeedDefaultTags {
            try await canonicalService.seedDefaultTagsIfNeeded(
                cloudKitEnabled: syncStatusService.cloudKitEnabled
            )
        }
    }

    private static func launchRestoreSuccessMessage(
        context: BackupPendingRestoreContext
    ) -> String {
        var message = "已恢复到 \(dateFormatter.string(from: context.selectedCreatedAt)) 的本机内容。"
        if let safetyCreatedAt = context.restoreSafetyCreatedAt {
            message += " 已保存 \(dateFormatter.string(from: safetyCreatedAt)) 的恢复前备份。"
        }
        return message
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()
}
