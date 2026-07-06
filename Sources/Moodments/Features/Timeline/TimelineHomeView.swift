import SwiftData
import SwiftUI

/// 首页时间轴（见 04-screen-specs.md §4.1）：唯一一级页面，聊天气泡式时间轴 + 顶部三入口 +
/// 底部悬浮新建按钮；空数据态展示 3 条预置引导 Moment（见 `GuidedMoment`）。
///
/// **左滑删除用成熟方案 `List` + `.swipeActions`**（阶段 4 决策，用户裁定：禁止自定义
/// `DragGesture` 手搓滑动删除）：容器由 `ScrollView { LazyVStack }` 迁移为 `List`，用
/// `.listStyle(.plain)` + `.scrollContentBackground(.hidden)` + 逐行 `.listRowSeparator(.hidden)`
/// / `.listRowBackground(.clear)` / `.listRowInsets(...)` 还原原有气泡时间轴视觉（不使用系统
/// 分组列表外观），真实 Moment 行的删除动作见 `TimelineRowView.SwipeToDeleteModifier`。
///
/// **标题两态折叠的实现取舍**：未借助系统 large title 的折叠行为——系统折叠后的 inline 标题
/// 是纯文本，无法只在收起态附加"可点、打开筛选"的语义，与裁决 B（展开态纯标识不可点 /
/// 收起态才是筛选入口）冲突。改为：展开态大标题作为 `List` 的首行（普通 `Text`，随内容自然
/// 滚出），用 `PreferenceKey` 追踪其相对滚动容器顶部的偏移量（iOS 18+ 改用更可靠的
/// `onScrollGeometryChange`，`List` 与 `ScrollView` 同样受支持）；顶部另有一条通过
/// `.safeAreaInset(edge: .top)` 固定不滚动的三入口栏，仅当偏移量越过阈值（判定为"已折叠"）
/// 才在其居中位置显示可点的收起态「时刻 ⌄」按钮，点击打开 `FilterPanelView`（就近浮窗，
/// 局部 `@State` 驱动、不进 `AppRouter`，见 08-architecture.md §2.2/§3）。
struct TimelineHomeView: View {
    private static let scrollSpace = "TimelineHomeView.scroll"
    // 折叠阈值取接近大标题实际高度：仅当展开态大标题大体滚出后才切收起态，
    // 避免小阈值下「时刻 ⌄」与仍完整可见的大标题同屏并存（见 code review）。
    private static let collapseThreshold: CGFloat = -44

    @Environment(AppRouter.self) private var router
    @Environment(ThemeManager.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @State private var timelineModel = TimelineModel()
    @State private var isTitleCollapsed = false
    @State private var isFilterPresented = false

    @Query(
        filter: #Predicate<Moment> { $0.deletedFlag == false },
        sort: \Moment.occurredAt,
        order: .reverse
    )
    private var moments: [Moment]

    /// 空态展示预置引导 Moment；一旦有真实记录即改为展示真实数据（见 02-information-architecture.md）。
    private var entries: [TimelineEntry] {
        moments.isEmpty ? GuidedMoment.all.map(TimelineEntry.guided) : moments.map(TimelineEntry.real)
    }

    var body: some View {
        ZStack {
            theme.canvasBackground.ignoresSafeArea()

            List {
                expandedTitle
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    // iOS 17 兜底的偏移探针：随首行滚出，其顶部相对滚动容器的 minY 随上滑变负。
                    // iOS 18+ 改用更可靠的 onScrollGeometryChange（见 TitleCollapseObserver）。
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TimelineScrollOffsetKey.self,
                                value: proxy.frame(in: .named(Self.scrollSpace)).minY
                            )
                        }
                    )

                ForEach(entries) { entry in
                    TimelineRowView(
                        entry: entry,
                        onTap: {
                            if case let .real(moment) = entry {
                                router.rootSheet = .preview(moment.id)
                            }
                        },
                        onDelete: entry.isGuided ? nil : { handleDelete(entry) }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                }
            }
            .listStyle(.plain)
            .listRowSpacing(0)
            .scrollContentBackground(.hidden)
            .coordinateSpace(name: Self.scrollSpace)
            .modifier(TitleCollapseObserver(threshold: Self.collapseThreshold, isCollapsed: $isTitleCollapsed))
            .safeAreaInset(edge: .top, spacing: 0) {
                topBar
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
        .environment(timelineModel)
    }

    /// 首页左滑删除 = 软删除进垃圾箱，无需二次确认（垃圾箱兜底，见公理3「删除是生命周期」）；
    /// 不释放篇数额度（见 07-data-persistence.md §3）；缩略图缓存不动（原图仍在，仅移出主时间轴）。
    private func handleDelete(_ entry: TimelineEntry) {
        guard case let .real(moment) = entry else { return }
        let momentID = moment.id
        Task {
            do {
                try await MomentRepository(modelContainer: modelContext.container).softDelete(id: momentID)
            } catch {
                assertionFailure("时间轴左滑删除失败：\(error)")
            }
        }
    }

    /// 新建入口的篇数额度前置闸门（见 03-user-flows.md §3.1）：点击悬浮按钮时先用
    /// `MomentRepository.totalMomentCount()`（含垃圾箱，见 07 §3）+ `QuotaService` 判定，
    /// 允许才打开编辑器，超额直接改为弹出 Paywall（编辑器不会被打开），限额判定只消费
    /// `QuotaService` 结果、不在 View 层自行比较数值（见 08-architecture.md §6）。
    private func handleNewMomentTapped() {
        Task {
            do {
                let repository = MomentRepository(modelContainer: modelContext.container)
                let count = try await repository.totalMomentCount()
                switch QuotaService().checkCanCreateMoment(currentMomentCount: count) {
                case .allowed:
                    router.rootSheet = .editor(.create)
                case .exceeded:
                    router.rootSheet = .paywall(.quotaMoment)
                }
            } catch {
                assertionFailure("篇数额度前置校验失败：\(error)")
            }
        }
    }

    // MARK: - 标题两态（见 04-screen-specs.md §4.1）

    /// 展开态：滚到顶时的大标题，纯场景标识，不可点、不触发筛选。
    private var expandedTitle: some View {
        Text("时刻")
            .font(AppTypography.pageTitle)
            .foregroundStyle(theme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("timelineExpandedTitle")
            .accessibilityAddTraits(.isHeader)
            // 折叠后展开态大标题虽仍在层级中（List 首行），对无障碍/自动化隐藏，
            // 避免与收起态「时刻」并存造成 VoiceOver 重复播报页头（见 review）。
            .accessibilityHidden(isTitleCollapsed)
    }

    /// 收起态：上滑折叠后固定栏中显示的「时刻 ⌄」，仅此状态可点、打开筛选就近浮窗。
    private var collapsedTitleButton: some View {
        Button {
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
            FilterPanelView()
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

/// 追踪展开态大标题相对滚动容器顶部的偏移量，驱动标题两态折叠判定（仅本文件内使用，iOS 17 兜底路径）。
private struct TimelineScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 监听时间轴滚动、驱动标题两态折叠：
/// - iOS 18+：用系统 `onScrollGeometryChange` 直接读取 contentOffset（可靠、为此而生，
///   对 `List` 与 `ScrollView` 同样适用）；
/// - iOS 17：回退到 `TimelineScrollOffsetKey` 偏移探针 + `onPreferenceChange`。
///
/// 折叠判定：内容自顶部下滑超过 `|threshold|` 点即判定为收起态（`threshold` 为负，见调用处）。
private struct TitleCollapseObserver: ViewModifier {
    let threshold: CGFloat
    @Binding var isCollapsed: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                // 顶部时 contentOffset.y == -contentInsets.top，二者相加为 0；下滑后为正。
                geometry.contentOffset.y + geometry.contentInsets.top > -threshold
            } action: { _, collapsed in
                isCollapsed = collapsed
            }
        } else {
            content.onPreferenceChange(TimelineScrollOffsetKey.self) { offset in
                isCollapsed = offset < threshold
            }
        }
    }
}

#Preview {
    TimelineHomeView()
        .environment(AppRouter())
        .environment(ThemeManager())
        // swiftlint:disable:next force_try
        .modelContainer(try! ModelContainerConfig.makeInMemoryContainer())
}
