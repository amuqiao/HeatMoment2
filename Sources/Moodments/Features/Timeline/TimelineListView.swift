import SwiftData
import SwiftUI

/// 时间轴 `List` 数据子视图（阶段5从 `TimelineHomeView` 抽出，见
/// `docs/plans/implementation-plan.md` 阶段5「必要重构」）：动态 `@Query`=f(`filter`)
/// + `ScrollViewReader`=f(`heatmapFocusDate`, 当前可见集) 两条链路彼此独立、互不引用，
/// 是「定位 ≠ 筛选」（公理2）在本视图层的结构化落实：
///
/// - `@Query` 的谓词由 `TimelineQuery.predicate(for: filter)` 生成，签名内没有任何 `Date`
///   参数，`filter` 变化时 `init(filter:)` 重新执行、`@Query` 重新取数——**这条链路从未读过
///   `heatmapFocusDate`**。
/// - 滚动定位由 `.onChange(of: timelineModel.heatmapFocusDate)` 驱动，只从当前
///   `entries`（已经历完筛选的可见集）里用纯函数 `TimelineQuery.scrollTargetID(for:in:)`
///   挑一个 id 滚过去，**这条链路从未写过 `@Query` 谓词、也不改变 `entries`**。
///
/// 标签 AND 交集（`@Query` 谓词表达不了的部分）在 `matchedMoments` 里用
/// `FilterCondition.matches` 内存过滤（见 04-screen-specs.md §4.2）。
struct TimelineListView: View {
    private static let scrollSpace = "TimelineListView.scroll"
    // 折叠阈值取接近大标题实际高度：仅当展开态大标题大体滚出后才切收起态，
    // 避免小阈值下「时刻 ⌄」与仍完整可见的大标题同屏并存（见阶段2 code review）。
    private static let collapseThreshold: CGFloat = -44

    /// 定位命中行的高亮叠加透明度（见 05-design-system.md「选中列整列高亮...建议用主色
    /// 12–16% 透明度叠加」，取值已登记 `docs/design/13-open-questions.md` 待真机复核）。
    private static let locateHighlightOpacity: Double = 0.14

    let filter: FilterCondition?
    @Binding var isTitleCollapsed: Bool

    @Environment(AppRouter.self) private var router
    @Environment(TimelineModel.self) private var timelineModel
    @Environment(ThemeManager.self) private var theme
    @Environment(\.modelContext) private var modelContext

    @Query private var moments: [Moment]

    init(filter: FilterCondition?, isTitleCollapsed: Binding<Bool>) {
        self.filter = filter
        _isTitleCollapsed = isTitleCollapsed
        _moments = Query(
            filter: TimelineQuery.predicate(for: filter),
            sort: \Moment.occurredAt,
            order: .reverse
        )
    }

    /// 标签 AND 交集在内存判定（复用 `FilterCondition.matches`，见类型头部说明）；
    /// `@Query` 已经把「未删除 + 心情命中」过滤好，这里只需再叠加标签维度。
    private var matchedMoments: [Moment] {
        guard let filter else { return moments }
        return moments.filter { filter.matches(tagIDs: Set($0.tags.map(\.id)), mood: $0.mood) }
    }

    /// 空态展示预置引导 Moment，仅当**未筛选且真的一条真实记录都没有**时触发
    /// （与阶段2语义完全一致：`filter == nil` 时 `moments` 就是「未删除全量」，
    /// 为空即代表用户从未记录过，见 02-information-architecture.md）。
    private var entries: [TimelineEntry] {
        if filter == nil, moments.isEmpty {
            return GuidedMoment.all.map(TimelineEntry.guided)
        }
        return matchedMoments.map(TimelineEntry.real)
    }

    /// 筛选后 0 条命中（区别于「从未记录过」的引导空态），见 04-screen-specs.md §4.1 状态、
    /// 03-user-flows.md §3.3「筛选后 0 条命中时...展示对应空态文案」。
    private var isFilteredEmpty: Bool { filter != nil && matchedMoments.isEmpty }

    /// 当前定位命中的行 id（供逐行高亮），纯粹由 `heatmapFocusDate` + 当前 `entries` 派生，
    /// 不引入独立存储、不影响 `entries` 本身内容。
    private var highlightedID: UUID? {
        guard let date = timelineModel.heatmapFocusDate else { return nil }
        return TimelineQuery.scrollTargetID(for: date, in: entries)
    }

    var body: some View {
        ScrollViewReader { proxy in
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

                if isFilteredEmpty {
                    filteredEmptyState
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                } else {
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
                        .id(entry.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            highlightedID == entry.id ? theme.accent.opacity(Self.locateHighlightOpacity) : Color.clear
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    }
                }
            }
            .listStyle(.plain)
            .listRowSpacing(0)
            .scrollContentBackground(.hidden)
            .coordinateSpace(name: Self.scrollSpace)
            .modifier(TitleCollapseObserver(threshold: Self.collapseThreshold, isCollapsed: $isTitleCollapsed))
            .onChange(of: timelineModel.heatmapFocusDate) { _, newValue in
                guard let newValue, let targetID = TimelineQuery.scrollTargetID(for: newValue, in: entries) else {
                    return
                }
                withAnimation {
                    proxy.scrollTo(targetID, anchor: .center)
                }
            }
        }
    }

    private var filteredEmptyState: some View {
        Text("没有符合条件的记录")
            .font(AppTypography.body)
            .foregroundStyle(theme.bubbleBodyText)
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
            .accessibilityIdentifier("timelineFilteredEmptyState")
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
            // 避免与收起态「时刻」并存造成 VoiceOver 重复播报页头（见阶段2 review）。
            .accessibilityHidden(isTitleCollapsed)
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
    TimelineListView(filter: nil, isTitleCollapsed: .constant(false))
        .environment(AppRouter())
        .environment(ThemeManager())
        .environment(TimelineModel())
        // swiftlint:disable:next force_try
        .modelContainer(try! ModelContainerConfig.makeInMemoryContainer())
}
