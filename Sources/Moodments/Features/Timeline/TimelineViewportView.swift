import SwiftData
import SwiftUI
import UIKit

/// 时间轴 viewport：动态 `@Query`=f(`filter`)
/// + `ScrollViewReader`=f(`heatmapFocusDate`, 粒度, 当前可见集) 两条链路彼此独立、互不引用，
/// 是「定位 ≠ 筛选」（公理2）在本视图层的结构化落实：
///
/// - `@Query` 的谓词由 `TimelineQuery.predicate(for: filter)` 生成，签名内没有任何 `Date`
///   参数，`filter` 变化时 `init(filter:)` 重新执行、`@Query` 重新取数——**这条链路从未读过
///   `heatmapFocusDate`**。
/// - 滚动定位由派生出的 `highlightedID` 变化驱动，只从当前 `entries`（已经历完筛选的可见集）
///   里用纯函数 `TimelineQuery.scrollTargetID(for:granularity:in:)` 挑一个 id 滚过去，**这条链路从未写过
///   `@Query` 谓词、也不改变 `entries`**。
///
/// 标签 AND 交集（`@Query` 谓词表达不了的部分）在 `matchedMoments` 里用
/// `FilterCondition.matches` 内存过滤（见 04-screen-specs.md §4.2）。
struct TimelineViewportView: View {
    private static let geometry = TimelineGeometry.standard
    // 折叠阈值取接近大标题实际高度：仅当展开态大标题大体滚出后才切收起态，
    // 避免小阈值下「时刻 ⌄」与仍完整可见的大标题同屏并存（见阶段2 code review）。
    private static let collapseThreshold: CGFloat = -44

    /// 定位命中行的高亮叠加透明度（见 05-design-system.md「选中列整列高亮...建议用主色
    /// 12–16% 透明度叠加」，取值已登记 `docs/design/13-open-questions.md` 待真机复核）。
    private static let locateHighlightOpacity: Double = 0.14

    let filter: FilterCondition?
    let suppressAccessibility: Bool
    @Binding var isTitleCollapsed: Bool
    @State private var scrollOffsetY: CGFloat = 0

    @Environment(AppRouter.self) private var router
    @Environment(TimelineModel.self) private var timelineModel
    @Environment(ThemeManager.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(SyncStatusService.self) private var syncStatusService

    @Query private var moments: [Moment]

    init(
        filter: FilterCondition?, suppressAccessibility: Bool = false,
        isTitleCollapsed: Binding<Bool>
    ) {
        self.filter = filter
        self.suppressAccessibility = suppressAccessibility
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
        return TimelineQuery.scrollTargetID(
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
            ZStack(alignment: .topLeading) {
                TimelineRailLayer(
                    geometry: Self.geometry,
                    railX: Self.geometry.initialRailCenterX,
                    initialTopY: Self.geometry.initialRailTopY,
                    scrollOffsetY: scrollOffsetY
                )

                List {
                    expandedTitle
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(Self.geometry.rowInsets)
                        .accessibilityHidden(suppressAccessibility)

                    timelineLeadIn

                    if isFilteredEmpty {
                        filteredEmptyState
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(Self.geometry.rowInsets)
                            .accessibilityHidden(suppressAccessibility)
                    } else {
                        ForEach(entries) { entry in
                            TimelineRowView(
                                entry: entry,
                                geometry: Self.geometry,
                                onTap: {
                                    if let momentID = entry.momentID {
                                        router.rootSheet = .preview(momentID)
                                    }
                                },
                                onDelete: entry.momentID == nil ? nil : { handleDelete(entry) }
                            )
                            .id(entry.id)
                            .listRowSeparator(.hidden)
                            .listRowBackground(
                                highlightedID == entry.id
                                    ? theme.accent.opacity(Self.locateHighlightOpacity)
                                    : Color.clear
                            )
                            .listRowInsets(Self.geometry.rowInsets)
                            .accessibilityHidden(suppressAccessibility)
                        }

                        timelineBottomOvershoot
                    }
                }
                .listStyle(.plain)
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
            }
        }
    }

    private var timelineLeadIn: some View {
        Color.clear
            .frame(height: Self.geometry.railLeadInHeight)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(Self.geometry.rowInsets)
            .accessibilityHidden(true)
    }

    private var timelineBottomOvershoot: some View {
        Color.clear
            .frame(height: Self.geometry.railBottomOvershoot)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(Self.geometry.rowInsets)
            .accessibilityHidden(true)
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
        guard let momentID = entry.momentID else { return }
        Task {
            do {
                let repository = MomentRepository(modelContainer: modelContext.container)
                try await repository.softDelete(id: momentID)
                // 软删除也是一次本地写入，驱动设置页 iCloud 行短暂展示「同步中」三态
                // （见 `SyncStatusService.noteLocalWrite()` 头部说明，阶段7 review 建议9）。
                syncStatusService.noteLocalWrite()
            } catch {
                // `@Query` 是真相源：删除失败时它本就不会反映出该行已消失，不需要额外回滚
                // 本地状态（见阶段6计划决策3：可恢复写失败改走统一错误通道）。
                await errorPresenter.report(message: "删除失败，请稍后重试。", underlying: error)
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
            // 折叠后展开态大标题虽仍在滚动内容中，对无障碍/自动化隐藏，
            // 避免与收起态「时刻」并存造成 VoiceOver 重复播报页头（见阶段2 review）。
            .accessibilityHidden(isTitleCollapsed)
    }
}

/// 监听时间轴滚动位置，驱动标题两态折叠和轨道混合纵向行为。
///
/// 折叠判定：内容自顶部上滑超过 `|threshold|` 点即判定为收起态（`threshold` 为负，见调用处）。
private struct TimelineScrollObserver: ViewModifier {
    let threshold: CGFloat
    @Binding var isCollapsed: Bool
    @Binding var scrollOffsetY: CGFloat

    private struct TimelineScrollState: Equatable {
        let isCollapsed: Bool
        let offsetY: CGFloat
    }

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: TimelineScrollState.self) { geometry in
                // 顶部时 contentOffset.y == -contentInsets.top，二者相加为 0；上滑后为正。
                let offsetY = geometry.contentOffset.y + geometry.contentInsets.top
                return TimelineScrollState(
                    isCollapsed: offsetY > -threshold,
                    offsetY: offsetY
                )
            } action: { _, state in
                isCollapsed = state.isCollapsed
                scrollOffsetY = state.offsetY
            }
        } else {
            content.background(
                TimelineScrollOffsetReader { offsetY in
                    isCollapsed = offsetY > -threshold
                    scrollOffsetY = offsetY
                }
                .frame(width: 0, height: 0)
            )
        }
    }
}

/// iOS 17 没有 `onScrollGeometryChange`，这里用一个零尺寸 UIView 挂到 `List` 自身，
/// 直接读取承载它的 `UIScrollView` 偏移；它只负责滚动状态，不参与轨道定位。
private struct TimelineScrollOffsetReader: UIViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> OffsetReaderView {
        let view = OffsetReaderView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: OffsetReaderView, context: Context) {
        uiView.onChange = onChange
        uiView.attachIfNeeded()
    }

    final class OffsetReaderView: UIView {
        var onChange: (CGFloat) -> Void = { _ in }

        private weak var observedScrollView: UIScrollView?
        private var contentOffsetObservation: NSKeyValueObservation?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachIfNeeded()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            emitCurrentOffset()
        }

        func attachIfNeeded() {
            DispatchQueue.main.async { [weak self] in
                self?.attachToEnclosingScrollView()
            }
        }

        private func attachToEnclosingScrollView() {
            guard let scrollView = enclosingScrollView(), scrollView !== observedScrollView else {
                emitCurrentOffset()
                return
            }

            observedScrollView = scrollView
            contentOffsetObservation = scrollView.observe(
                \.contentOffset,
                options: [.initial, .new]
            ) { [weak self, weak scrollView] _, _ in
                DispatchQueue.main.async {
                    guard let scrollView else { return }
                    self?.emit(scrollView)
                }
            }
        }

        private func emitCurrentOffset() {
            guard let observedScrollView else { return }
            emit(observedScrollView)
        }

        private func emit(_ scrollView: UIScrollView) {
            onChange(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
        }

        private func enclosingScrollView() -> UIScrollView? {
            var view = superview
            while let candidate = view {
                if let scrollView = candidate as? UIScrollView {
                    return scrollView
                }
                view = candidate.superview
            }
            return nil
        }
    }
}

#Preview {
    TimelineViewportView(filter: nil, isTitleCollapsed: .constant(false))
        .environment(AppRouter())
        .environment(ThemeManager())
        .environment(TimelineModel())
        .environment(ErrorPresenter())
        .environment(SyncStatusService(cloudKitEnabled: false))
        // swiftlint:disable:next force_try
        .modelContainer(try! ModelContainerConfig.makeInMemoryContainer())
}
