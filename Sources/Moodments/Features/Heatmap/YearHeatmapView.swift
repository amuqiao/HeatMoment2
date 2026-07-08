import SwiftData
import SwiftUI

/// 年度心情热力图主页顶部上下文区（见 `docs/design/04-screen-specs.md` §4.3、
/// `docs/design/08-architecture.md` §2.2：导航栏下方原位展开、非模态、不入 Router）。
///
/// **呈现形态（P0 落地）**：由 `TimelineHomeView` 的顶部 `safeAreaInset` 原位呈现，继承
/// `theme.canvasBackground`，不是全屏黑遮罩模态，也不是漂浮卡片。
///
/// **与筛选正交**（公理2）：点月/点日只写 `TimelineModel.heatmapFocusDate`（驱动滚动），
/// 从不读写 `activeFilter`；年度聚合虽然**读** `activeFilter` 作为聚合口径（阶段5决策1），
/// 但这只影响「热力图展示哪些数据」，与「点格改变滚动位置」这条定位语义完全分离，
/// 两条链路（`YearHeatmapModel.load(filter:)` 的聚合 vs `handleSelectDay` 的定位）互不引用。
struct YearHeatmapView: View {
    @Environment(TimelineModel.self) private var timelineModel
    @Environment(ThemeManager.self) private var theme
    @State private var heatmapModel: YearHeatmapModel
    let onClose: () -> Void

    init(modelContainer: ModelContainer, onClose: @escaping () -> Void = {}) {
        _heatmapModel = State(initialValue: YearHeatmapModel(modelContainer: modelContainer))
        self.onClose = onClose
    }

    /// `.task(id:)` 的复合 key：年份或筛选条件任一变化都应重新聚合。
    private struct LoadKey: Equatable {
        let year: Int
        let filter: FilterCondition?
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            if heatmapModel.moodByDay.isEmpty {
                emptyState
            } else {
                HeatmapGridView(
                    year: heatmapModel.year,
                    moodByDay: heatmapModel.moodByDay,
                    selectedDate: timelineModel.heatmapFocusDate,
                    selectedGranularity: timelineModel.heatmapAnchorGranularity,
                    onSelectDay: handleSelectDay,
                    onSelectMonth: handleSelectMonth
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(HomeSceneBackgroundView())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.heatmapSeparator)
                .frame(height: 0.5)
        }
        .task(id: LoadKey(year: heatmapModel.year, filter: timelineModel.activeFilter)) {
            do {
                try await heatmapModel.load(filter: timelineModel.activeFilter)
            } catch {
                assertionFailure("热力图聚合加载失败：\(error)")
            }
        }
        // 注：不在本容器上叠加 `.accessibilityIdentifier`——实测（见 `FilterPanelView` 同类
        // 教训）容器级 identifier 会覆盖后代交互元素（`heatmapCloseButton`/`heatmapYearMenu`/
        // `HeatmapGridView` 各日期格）自己的 identifier，宁可不设容器级 id。
    }

    private var header: some View {
        HStack {
            yearMenu
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(theme.secondaryText)
            }
            .accessibilityLabel(Text("关闭"))
            .accessibilityIdentifier("heatmapCloseButton")
        }
    }

    private var yearMenu: some View {
        Menu {
            ForEach(HeatmapYearRange.availableYears.reversed(), id: \.self) { year in
                Button {
                    handleSelectYear(year)
                } label: {
                    Text(verbatim: String(year))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: String(heatmapModel.year))
                Image(systemName: "chevron.up.chevron.down")
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(theme.accent)
        }
        .accessibilityIdentifier("heatmapYearMenu")
        .accessibilityLabel(Text("年份，\(heatmapModel.year)"))
        .accessibilityAdjustableAction { direction in
            let years = HeatmapYearRange.availableYears
            guard let index = years.firstIndex(of: heatmapModel.year) else { return }
            switch direction {
            case .increment where index + 1 < years.count:
                handleSelectYear(years[index + 1])
            case .decrement where index > 0:
                handleSelectYear(years[index - 1])
            default:
                break
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.stars")
                .font(.largeTitle)
                .foregroundStyle(theme.secondaryText)
            Text("这些天没有日记哦")
                .font(AppTypography.body)
                .foregroundStyle(theme.bubbleBodyText)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .accessibilityIdentifier("heatmapEmptyState")
    }

    /// 切换年份：换整年回看范围、清除时间锚点（见 04-screen-specs.md §4.3）。
    private func handleSelectYear(_ year: Int) {
        heatmapModel.year = year
        timelineModel.clearHeatmapAnchor()
    }

    /// 点格定位：日锚点取当天最新一条——传入当天 23:59:59，`TimelineQuery.scrollTargetID`
    /// 据此挑出「occurredAt <= 当天末刻」中最大的一条，即当天最晚记录（见阶段5计划决策4、
    /// `TimelineQuery` 头部说明）；再次点击同一天 → `heatmapFocusDate = nil` 取消定位
    /// （不主动滚动、不撤销已发生的滚动位置，只清高亮，见 04 §4.3）。
    private func handleSelectDay(_ date: Date) {
        let calendar = Calendar.current
        if timelineModel.heatmapAnchorGranularity == .day,
           let current = timelineModel.heatmapFocusDate,
           calendar.isDate(current, inSameDayAs: date) {
            timelineModel.clearHeatmapAnchor()
            return
        }
        guard let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date) else {
            assertionFailure("日期锚点合成失败：\(date)")
            return
        }
        timelineModel.setHeatmapAnchor(endOfDay, granularity: .day)
    }

    /// 点月定位：月锚点取该月最后一刻，`TimelineQuery.scrollTargetID` 会在当前可见集里挑出
    /// 同月且 `occurredAt <= 月末` 的最新真实记录；再次点击同一月取消定位。
    private func handleSelectMonth(_ date: Date) {
        let calendar = Calendar.current
        if timelineModel.heatmapAnchorGranularity == .month,
           let current = timelineModel.heatmapFocusDate,
           calendar.isDate(current, equalTo: date, toGranularity: .month) {
            timelineModel.clearHeatmapAnchor()
            return
        }
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: date),
            let monthEnd = calendar.date(byAdding: .second, value: -1, to: monthInterval.end)
        else {
            assertionFailure("月份锚点合成失败：\(date)")
            return
        }
        timelineModel.setHeatmapAnchor(monthEnd, granularity: .month)
    }
}

#Preview {
    // swiftlint:disable:next force_try
    YearHeatmapView(modelContainer: try! ModelContainerConfig.makeInMemoryContainer())
        .environment(TimelineModel())
        .environment(ThemeManager())
}
