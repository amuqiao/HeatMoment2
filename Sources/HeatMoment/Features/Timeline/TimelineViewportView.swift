import SwiftUI

/// 时间轴 viewport：canonical reload=f(`filter`, `changeToken`)
/// + `ScrollViewReader`=f(`heatmapFocusDate`, 粒度, 当前可见集) 两条链路彼此独立、互不引用，
/// 是「定位 ≠ 筛选」（公理2）在本视图层的结构化落实：
///
/// - canonical 查询只消费 `filter` 和资料库变更版本；`heatmapFocusDate` 不参与查询条件。
/// - 滚动定位由派生出的 `highlightedID` 变化驱动，只从当前 `entries`（已经历完筛选的可见集）
///   里用纯函数 `TimelineLocator.scrollTargetID(for:granularity:in:)` 挑一个 id 滚过去，**这条链路从未写过
///   查询条件、也不改变 `entries`**。
struct TimelineViewportView: View {
    // 折叠阈值取接近大标题实际高度：仅当展开态大标题大体滚出后才切收起态，
    // 避免小阈值下「时刻 ⌄」与仍完整可见的大标题同屏并存（见阶段2 code review）。
    private static let collapseThreshold: CGFloat = -44

    /// 定位命中行的高亮叠加透明度（见 docs/current/implementation-truth.md「选中列整列高亮...建议用主色
    /// 12–16% 透明度叠加」，取值已登记 `docs/plans/README.md` 待真机复核）。
    private static let locateHighlightOpacity: Double = 0.14

    let filter: FilterCondition?
    let scene: TimelineSceneMetrics
    let suppressAccessibility: Bool
    @Binding var isTitleCollapsed: Bool

    @Environment(AppRouter.self) private var router
    @Environment(TimelineModel.self) private var timelineModel
    @Environment(ThemeManager.self) private var theme
    @Environment(CanonicalLibraryService.self) private var canonicalService
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(SyncStatusService.self) private var syncStatusService
    @Environment(\.canonicalRecoveryCoordinator) private var canonicalRecoveryCoordinator
    @State private var scrollOffsetY: CGFloat = 0
    @State private var realEntries: [TimelineEntry] = []
    @State private var isLoaded = false

    private struct LoadKey: Equatable {
        let filter: FilterCondition?
        let changeToken: Int
    }

    init(
        filter: FilterCondition?,
        scene: TimelineSceneMetrics,
        suppressAccessibility: Bool = false,
        isTitleCollapsed: Binding<Bool>
    ) {
        self.filter = filter
        self.scene = scene
        self.suppressAccessibility = suppressAccessibility
        _isTitleCollapsed = isTitleCollapsed
    }

    private var entries: [TimelineEntry] {
        realEntries
    }

    /// 筛选后 0 条命中（区别于真正空库），见 docs/current/implementation-truth.md §4.1 状态、
    /// docs/product-mental-model.md §3.3「筛选后 0 条命中时...展示对应空态文案」。
    private var isFilteredEmpty: Bool { filter != nil && isLoaded && realEntries.isEmpty }
    private var isUnfilteredEmpty: Bool { filter == nil && isLoaded && realEntries.isEmpty }

    /// 当前定位命中的行 id（供逐行高亮），纯粹由 `heatmapFocusDate` + 当前 `entries` 派生，
    /// 不引入独立存储、不影响 `entries` 本身内容。
    private var highlightedID: UUID? {
        guard let date = timelineModel.heatmapFocusDate else { return nil }
        return TimelineLocator.scrollTargetID(
            for: date,
            granularity: timelineModel.heatmapAnchorGranularity ?? .day,
            in: entries
        )
    }

    private struct LocateScrollRequest: Equatable {
        let focusDate: Date
        let granularity: HeatmapAnchorGranularity
        let targetID: UUID?
    }

    /// 滚动请求必须保留 anchor 本身，而不只保留 target row id。否则“月 anchor”和“日 anchor”
    /// 命中同一条记录时，用户手动滚走后再次点选不会重新触发滚动。
    private var locateScrollRequest: LocateScrollRequest? {
        guard let date = timelineModel.heatmapFocusDate else { return nil }
        return LocateScrollRequest(
            focusDate: date,
            granularity: timelineModel.heatmapAnchorGranularity ?? .day,
            targetID: highlightedID
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            let viewportEntries = entries
            let railVisibility = TimelineRailVisibility.resolve(
                visibleReadingUnitCount: viewportEntries.count,
                isFilteredEmpty: isFilteredEmpty
            )

            GeometryReader { viewportProxy in
                let viewportMetrics = TimelineViewportMetrics(
                    viewportSize: viewportProxy.size,
                    scrollOffsetY: scrollOffsetY,
                    sceneLayout: scene.layout
                )

                ZStack(alignment: .topLeading) {
                    if railVisibility.showsRail {
                        TimelineRailSceneLayer(
                            geometry: scene.layout.geometry,
                            metrics: viewportMetrics
                        )
                        .zIndex(0)
                    }

                    List {
                        timelineExpandedTitleRow(
                            geometry: scene.layout.geometry,
                            layout: scene.layout.viewport,
                            style: scene.style.title
                        )

                        if railVisibility.showsRail {
                            timelineFirstMomentLeadIn(
                                geometry: scene.layout.geometry,
                                layout: scene.layout.viewport
                            )
                        }

                        if isFilteredEmpty || isUnfilteredEmpty {
                            filteredEmptyState
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(scene.layout.geometry.rowInsets)
                                .accessibilityHidden(suppressAccessibility)
                        } else {
                            ForEach(Array(viewportEntries.enumerated()), id: \.element.id) {
                                index, entry in
                                TimelineRowView(
                                    entry: entry,
                                    dateDisplayMode: TimelineRowDateDisplayMode.resolve(
                                        entry: entry,
                                        previousEntry: previousEntry(
                                            before: index,
                                            in: viewportEntries
                                        )
                                    ),
                                    geometry: scene.layout.geometry,
                                    style: scene.style,
                                    onTap: {
                                        router.rootSheet = .preview(entry.id)
                                    },
                                    onDelete: { handleDelete(entry) }
                                )
                                .id(entry.id)
                                .listRowSeparator(.hidden)
                                .listRowBackground(rowBackground(for: entry))
                                .listRowInsets(scene.layout.geometry.rowInsets)
                                .accessibilityHidden(suppressAccessibility)
                            }

                            if railVisibility.showsRail {
                                timelineBottomTail(
                                    geometry: scene.layout.geometry,
                                    layout: scene.layout.viewport,
                                    bottomContentClearance: scene.layout.home.bottomActionClearance
                                )
                            }
                        }
                    }
                    .listStyle(.plain)
                    .environment(\.defaultMinListRowHeight, 0)
                    .listRowSpacing(0)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.horizontal, 0, for: .scrollContent)
                    .modifier(
                        TimelineScrollObserver(
                            threshold: Self.collapseThreshold,
                            isCollapsed: $isTitleCollapsed,
                            scrollOffsetY: $scrollOffsetY
                        )
                    )
                    .onChange(of: locateScrollRequest) { _, request in
                        guard let targetID = request?.targetID else { return }
                        withAnimation {
                            proxy.scrollTo(targetID, anchor: .center)
                        }
                    }
                    .task(
                        id: LoadKey(filter: filter, changeToken: canonicalService.changeToken)
                    ) {
                        await reload()
                    }
                    .zIndex(1)
                }
            }
        }
    }

    private func timelineExpandedTitleRow(
        geometry: TimelineGeometry,
        layout: TimelineViewportLayout,
        style: TimelineTitleStyle
    ) -> some View {
        expandedTitle(style: style)
            .frame(
                height: layout.expandedTitleContentSlotHeight,
                alignment: .bottomLeading
            )
            .padding(.top, layout.expandedTitleTopPadding)
            .padding(.bottom, layout.titleToRailTopGap)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(geometry.rowInsets)
            .accessibilityHidden(suppressAccessibility)
    }

    private func timelineFirstMomentLeadIn(
        geometry: TimelineGeometry,
        layout: TimelineViewportLayout
    ) -> some View {
        Color.clear
            .frame(height: layout.railTopToFirstMomentTopGap)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(geometry.rowInsets)
            .accessibilityHidden(true)
    }

    private func timelineBottomTail(
        geometry: TimelineGeometry,
        layout: TimelineViewportLayout,
        bottomContentClearance: CGFloat
    ) -> some View {
        Color.clear
            .frame(height: layout.bottomTailClearance(protecting: bottomContentClearance))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(geometry.rowInsets)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func rowBackground(for entry: TimelineEntry) -> some View {
        if highlightedID == entry.id {
            theme.accent
                .opacity(Self.locateHighlightOpacity)
                .allowsHitTesting(false)
        } else {
            Color.clear
        }
    }

    private func previousEntry(before index: Int, in entries: [TimelineEntry]) -> TimelineEntry? {
        guard index > 0 else { return nil }
        return entries[index - 1]
    }

    private var filteredEmptyState: some View {
        Text(isFilteredEmpty ? "没有符合条件的记录" : "还没有记录")
            .font(AppTypography.body)
            .foregroundStyle(theme.bubbleBodyText)
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
            .accessibilityIdentifier("timelineFilteredEmptyState")
    }

    /// 首页左滑删除 = 软删除进垃圾箱，无需二次确认（垃圾箱兜底，见公理3「删除是生命周期」）；
    /// 不释放篇数额度（见 docs/current/local-data-architecture.md §3）；缩略图缓存不动（原图仍在，仅移出主时间轴）。
    private func handleDelete(_ entry: TimelineEntry) {
        Task {
            do {
                try await mutationService.softDeleteMoment(id: entry.id)
            } catch {
                // canonical 是真相源：删除失败时可见集不会刷新为已删除，不需要额外回滚
                // 本地状态（见阶段6计划决策3：可恢复写失败改走统一错误通道）。
                errorPresenter.report(message: "删除失败，请稍后重试。", underlying: error)
            }
        }
    }

    private var mutationService: LocalLibraryMutationService {
        LocalLibraryMutationService(
            canonicalService: canonicalService,
            canonicalRecoveryCoordinator: canonicalRecoveryCoordinator,
            syncStatusService: syncStatusService,
            errorPresenter: errorPresenter
        )
    }

    private func reload() async {
        do {
            realEntries = try await canonicalService.fetchTimelineEntries(filter: filter)
            isLoaded = true
        } catch {
            isLoaded = true
            errorPresenter.report(message: "时间轴加载失败，请稍后重试。", underlying: error)
        }
    }

    // MARK: - 标题两态（见 docs/current/implementation-truth.md §4.1）

    /// 展开态：滚到顶时的大标题，纯场景标识，不可点、不触发筛选。
    private func expandedTitle(style: TimelineTitleStyle) -> some View {
        Text("时刻")
            .font(style.font)
            .foregroundStyle(theme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("timelineExpandedTitle")
            .accessibilityAddTraits(.isHeader)
            // 折叠后展开态大标题虽仍在滚动内容中，对无障碍/自动化隐藏，
            // 避免与收起态「时刻」并存造成 VoiceOver 重复播报页头（见阶段2 review）。
            .accessibilityHidden(isTitleCollapsed)
    }
}

#Preview {
    TimelineViewportView(
        filter: nil,
        scene: TimelineSceneMetrics.responsive(for: 390),
        isTitleCollapsed: .constant(false)
    )
    .environment(AppRouter())
    .environment(ThemeManager())
    .environment(TimelineModel())
    .environment(ErrorPresenter())
    .environment(SyncStatusService(cloudKitEnabled: false))
    .environment(CanonicalLibraryService.makeInMemoryForPreview())
}
