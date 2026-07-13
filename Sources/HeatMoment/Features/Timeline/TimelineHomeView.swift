import SwiftUI

/// 首页时间轴（见 docs/current/implementation-truth.md §4.1）：唯一一级页面，聊天气泡式时间轴 + 顶部三入口 +
/// 底部悬浮新建按钮；空数据态展示 3 条预置引导 Moment（见 `GuidedMoment`）。
///
/// **阶段5重构**：时间轴 viewport（含标题两态折叠、定位滚动、筛选谓词）已下沉到
/// `TimelineViewportView`（见该类型头部说明「定位 ≠ 筛选」的结构化落实）；本视图只保留
/// 顶部三入口 / 上下文标记横条 / 悬浮新建按钮这些「壳」，以及筛选就近浮窗的呈现。
/// `TimelineModel` 由 `RootView` 上提持有并注入（见 `TimelineModel` 头部注释「必要重构」），
/// 时间轴与热力图共享同一实例。
struct TimelineHomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(TimelineModel.self) private var timelineModel
    @Environment(ThemeManager.self) private var theme
    @Environment(CanonicalLibraryService.self) private var canonicalService
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(SubscriptionService.self) private var subscriptionService
    @State private var isTitleCollapsed = false
    @State private var isFilterPresented = false
    @State private var isHeatmapPresented = false

    private var isModalContextPresented: Bool {
        router.rootSheet != nil || isFilterPresented
    }

    var body: some View {
        @Bindable var timelineModel = timelineModel

        GeometryReader { proxy in
            let scene = TimelineSceneMetrics.responsive(
                for: proxy.size.width,
                baseStyle: .standard
            )

            ZStack {
                HomeSceneBackgroundView().ignoresSafeArea()

                TimelineViewportView(
                    filter: timelineModel.activeFilter,
                    scene: scene,
                    suppressAccessibility: isModalContextPresented,
                    isTitleCollapsed: $isTitleCollapsed
                )
                .safeAreaInset(edge: .top, spacing: 0) {
                    topBarStack(layout: scene.layout.home, style: scene.style.chromeIcon)
                }
            }
            .accessibilityHidden(isModalContextPresented)
            .overlay(alignment: .bottom) {
                FABButtonView(
                    diameter: scene.layout.home.fabDiameter,
                    style: scene.style.fab
                ) {
                    handleNewMomentTapped()
                }
                .padding(.bottom, scene.layout.home.fabBottomPadding)
                .accessibilityHidden(isModalContextPresented)
            }
        }
        .timelineFilterSheet(
            isPresented: $isFilterPresented,
            activeFilter: $timelineModel.activeFilter
        )
        .onAppear {
            timelineModel.noteTimelineContentChanged()
        }
        .onChange(of: canonicalService.changeToken) { _, _ in
            timelineModel.noteTimelineContentChanged()
        }
    }

    /// 顶部三入口 + 上下文标记横条：一起放进同一个 `.safeAreaInset(edge: .top)`，
    /// 使二者都固定在列表之外、不随内容滚走（见 docs/current/implementation-truth.md §4.1「上下文标记」）。
    private func topBarStack(layout: TimelineHomeLayout, style: HomeChromeIconStyle) -> some View {
        VStack(spacing: 0) {
            TimelineHomeChromeView(
                layout: layout,
                style: style,
                isTitleCollapsed: isTitleCollapsed,
                isContextPanelPresented: isHeatmapPresented,
                onCalendarTapped: {
                    isHeatmapPresented.toggle()
                },
                onFilterTapped: {
                    isFilterPresented = true
                },
                onSettingsTapped: {
                    router.rootSheet = .settings
                }
            )
            HomeContextPanel(isPresented: isHeatmapPresented) {
                YearHeatmapView(canonicalService: canonicalService) {
                    isHeatmapPresented = false
                }
            }
            if timelineModel.hasFilter || timelineModel.isLocated {
                TimelineContextMarkerBar(layout: layout)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isHeatmapPresented)
    }

    /// 新建入口的篇数额度前置闸门（见 docs/product-mental-model.md §3.1）：点击悬浮按钮时先
    /// `await subscriptionService.currentEntitlementIsPro()` 现场重查 Pro 权威判定（docs/current/implementation-truth.md §11.4，
    /// 阶段7计划决策1——不用缓存 `isPro`），再用 canonical repository 额度计数（含
    /// 垃圾箱，见 docs/current/local-data-architecture.md §3）+ `QuotaService` 判定，允许才打开编辑器，超额直接改为弹出 Paywall
    /// （编辑器不会被打开）。限额判定唯一落点仍是 `QuotaService`，本方法只负责把当次权威 Pro
    /// 判定结果适配成 `EntitlementProviding` 传入，不在 View 层自行比较数值（docs/current/implementation-truth.md §6）。
    private func handleNewMomentTapped() {
        Task {
            do {
                let isPro = await subscriptionService.currentEntitlementIsPro()
                let count = try await canonicalService.repository.totalMomentCount()
                let quotaService = QuotaService(
                    entitlementProvider: SubscriptionEntitlementProvider(isPro: isPro)
                )
                switch quotaService.checkCanCreateMoment(currentMomentCount: count) {
                case .allowed:
                    router.rootSheet = .editor(.create)
                case .exceeded:
                    router.rootSheet = .paywall(.quotaMoment)
                }
            } catch {
                errorPresenter.report(message: "创建前检查失败，请稍后重试。", underlying: error)
            }
        }
    }
}

#Preview {
    TimelineHomeView()
        .environment(AppRouter())
        .environment(ThemeManager())
        .environment(TimelineModel())
        .environment(ErrorPresenter())
        .environment(SubscriptionService())
        .environment(SyncStatusService(cloudKitEnabled: false))
        .environment(CanonicalLibraryService.makeInMemoryForPreview())
}
