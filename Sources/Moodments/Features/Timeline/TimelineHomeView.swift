import SwiftData
import SwiftUI

/// 首页时间轴（见 04-screen-specs.md §4.1）：唯一一级页面，聊天气泡式时间轴 + 顶部三入口 +
/// 底部悬浮新建按钮；空数据态展示 3 条预置引导 Moment（见 `GuidedMoment`）。
///
/// **标题两态折叠的实现取舍**：未借助系统 large title 的折叠行为——系统折叠后的 inline 标题
/// 是纯文本，无法只在收起态附加"可点、打开筛选"的语义，与裁决 B（展开态纯标识不可点 /
/// 收起态才是筛选入口）冲突。改为：展开态大标题作为普通 `Text` 直接放在可滚动内容顶部
/// （随内容自然滚出），用 `PreferenceKey` 追踪其相对滚动容器顶部的偏移量；顶部另有一条通过
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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    expandedTitle
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 12)

                    ForEach(entries) { entry in
                        TimelineRowView(entry: entry) {
                            if case let .real(moment) = entry {
                                router.rootSheet = .preview(moment.id)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 120)
                // iOS 17 兜底的偏移探针：覆盖 LazyVStack 全高、始终参与布局，其顶部相对滚动容器的
                // minY 随上滑变负。iOS 18+ 改用更可靠的 onScrollGeometryChange（见 TitleCollapseObserver）。
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TimelineScrollOffsetKey.self,
                            value: proxy.frame(in: .named(Self.scrollSpace)).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: Self.scrollSpace)
            .modifier(TitleCollapseObserver(threshold: Self.collapseThreshold, isCollapsed: $isTitleCollapsed))
            .safeAreaInset(edge: .top, spacing: 0) {
                topBar
            }
        }
        .overlay(alignment: .bottom) {
            FABButtonView {
                router.rootSheet = .editor(.create)
            }
            .padding(.bottom, 24)
        }
        .environment(timelineModel)
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
            // 折叠后展开态大标题虽仍在层级中（LazyVStack 顶部），对无障碍/自动化隐藏，
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
/// - iOS 18+：用系统 `onScrollGeometryChange` 直接读取 contentOffset（可靠、为此而生）；
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
