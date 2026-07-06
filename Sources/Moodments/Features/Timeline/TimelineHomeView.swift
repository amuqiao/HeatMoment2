import SwiftData
import SwiftUI

/// 首页时间轴（见 04-screen-specs.md §4.1）：唯一一级页面，聊天气泡式时间轴 + 顶部三入口 +
/// 底部悬浮新建按钮；空数据态展示 3 条预置引导 Moment（见 `GuidedMoment`）。
///
/// **阶段5重构**：`List` 数据本体（含标题两态折叠探针、定位滚动、筛选谓词）已下沉到
/// `TimelineListView`（见该类型头部说明「定位 ≠ 筛选」的结构化落实）；本视图只保留
/// 顶部三入口 / 上下文标记横条 / 悬浮新建按钮这些「壳」，以及筛选就近浮窗的呈现。
/// `TimelineModel` 由 `RootView` 上提持有并注入（见 `TimelineModel` 头部注释「必要重构」），
/// 时间轴与热力图覆盖层共享同一实例。
struct TimelineHomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme
    @Environment(TimelineModel.self) private var timelineModel
    @Environment(\.modelContext) private var modelContext
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(SubscriptionService.self) private var subscriptionService
    @State private var isTitleCollapsed = false
    @State private var isFilterPresented = false

    var body: some View {
        @Bindable var timelineModel = timelineModel

        ZStack {
            theme.canvasBackground.ignoresSafeArea()

            TimelineListView(filter: timelineModel.activeFilter, isTitleCollapsed: $isTitleCollapsed)
                .safeAreaInset(edge: .top, spacing: 0) {
                    topBarStack
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // 为悬浮新建按钮（FAB）预留空间，替代原 LazyVStack 尾部的 `.padding(.bottom, 120)`。
                    Color.clear.frame(height: 120)
                }
        }
        .overlay(alignment: .bottom) {
            FABButtonView {
                handleNewMomentTapped()
            }
            .padding(.bottom, 24)
        }
    }

    /// 顶部三入口 + 上下文标记横条：一起放进同一个 `.safeAreaInset(edge: .top)`，
    /// 使二者都固定在列表之外、不随内容滚走（见 04-screen-specs.md §4.1「上下文标记」）。
    private var topBarStack: some View {
        VStack(spacing: 0) {
            topBar
            if timelineModel.hasFilter || timelineModel.isLocated {
                TimelineContextMarkerBar()
            }
        }
    }

    /// 新建入口的篇数额度前置闸门（见 03-user-flows.md §3.1）：点击悬浮按钮时先
    /// `await subscriptionService.currentEntitlementIsPro()` 现场重查 Pro 权威判定（11 §11.4，
    /// 阶段7计划决策1——不用缓存 `isPro`），再用 `MomentRepository.totalMomentCount()`（含
    /// 垃圾箱，见 07 §3）+ `QuotaService` 判定，允许才打开编辑器，超额直接改为弹出 Paywall
    /// （编辑器不会被打开）。限额判定唯一落点仍是 `QuotaService`，本方法只负责把当次权威 Pro
    /// 判定结果适配成 `EntitlementProviding` 传入，不在 View 层自行比较数值（08 §6）。
    private func handleNewMomentTapped() {
        Task {
            do {
                let isPro = await subscriptionService.currentEntitlementIsPro()
                let repository = MomentRepository(modelContainer: modelContext.container)
                let count = try await repository.totalMomentCount()
                let quotaService = QuotaService(entitlementProvider: SubscriptionEntitlementProvider(isPro: isPro))
                switch quotaService.checkCanCreateMoment(currentMomentCount: count) {
                case .allowed:
                    router.rootSheet = .editor(.create)
                case .exceeded:
                    router.rootSheet = .paywall(.quotaMoment)
                }
            } catch {
                await errorPresenter.report(message: "创建前检查失败，请稍后重试。", underlying: error)
            }
        }
    }

    // MARK: - 收起态筛选入口（见 04-screen-specs.md §4.1 标题两态）

    /// 收起态：上滑折叠后固定栏中显示的「时刻 ⌄」，仅此状态可点、打开筛选就近浮窗，
    /// 绑定 `timelineModel.activeFilter`（不进 `AppRouter`，见 08-architecture.md §2.2/§3）。
    private var collapsedTitleButton: some View {
        @Bindable var timelineModel = timelineModel

        return Button {
            isFilterPresented = true
        } label: {
            HStack(spacing: 4) {
                Text("时刻")
                Image(systemName: "chevron.down")
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(theme.primaryText)
        }
        .accessibilityIdentifier("timelineCollapsedTitleButton")
        .accessibilityLabel(Text("时刻，筛选入口"))
        .accessibilityHint(Text("双击打开标签与心情筛选"))
        .popover(isPresented: $isFilterPresented, arrowEdge: .top) {
            FilterPanelView(activeFilter: $timelineModel.activeFilter)
                .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: - 顶部三入口（见 05-design-system.md §5.6）

    private var topBar: some View {
        HStack {
            CalendarIconButtonView {
                router.isHeatmapPresented = true
            }
            Spacer()
            if isTitleCollapsed {
                collapsedTitleButton
                    .transition(.opacity)
            }
            Spacer()
            HexagonIconButtonView {
                router.rootSheet = .settings
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            (isTitleCollapsed ? theme.canvasBackground.opacity(0.94) : Color.clear)
                .ignoresSafeArea(edges: .top)
        )
        .animation(.easeInOut(duration: 0.2), value: isTitleCollapsed)
    }
}

#Preview {
    TimelineHomeView()
        .environment(AppRouter())
        .environment(ThemeManager())
        .environment(TimelineModel())
        .environment(ErrorPresenter())
        .environment(SubscriptionService())
        // swiftlint:disable:next force_try
        .modelContainer(try! ModelContainerConfig.makeInMemoryContainer())
}
