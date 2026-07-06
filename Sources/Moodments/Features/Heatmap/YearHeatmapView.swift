import SwiftData
import SwiftUI

/// 年度心情热力图覆盖层（见 `docs/design/04-screen-specs.md` §4.3、
/// `docs/design/08-architecture.md` §2.2：`ZStack` overlay、非模态、顶部展开）。
///
/// **呈现形态（阶段5落地）**：由 `RootView` 以 `alignment: .top` 的 overlay 呈现、
/// `.move(edge: .top) + opacity` 转场、继承 `theme.canvasBackground`——不是全屏黑遮罩模态，
/// 背景时间轴不下沉不变暗，只在顶部展开一张卡片，符合「覆盖层≠任务卡片」的层级区分
/// （见 product-mental-model.md 公理4）。
///
/// **与筛选正交**（公理2）：`onSelectDay` 只写 `TimelineModel.heatmapFocusDate`（驱动滚动），
/// 从不读写 `activeFilter`；年度聚合虽然**读** `activeFilter` 作为聚合口径（阶段5决策1），
/// 但这只影响「热力图展示哪些数据」，与「点格改变滚动位置」这条定位语义完全分离，
/// 两条链路（`YearHeatmapModel.load(filter:)` 的聚合 vs `handleSelectDay` 的定位）互不引用。
struct YearHeatmapView: View {
    @Environment(AppRouter.self) private var router
    @Environment(TimelineModel.self) private var timelineModel
    @Environment(ThemeManager.self) private var theme
    @State private var heatmapModel: YearHeatmapModel

    init(modelContainer: ModelContainer) {
        _heatmapModel = State(initialValue: YearHeatmapModel(modelContainer: modelContainer))
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
                    onSelectDay: handleSelectDay
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(theme.canvasBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .padding(.horizontal, 12)
        .padding(.top, 8)
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
                router.isHeatmapPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(SemanticColor.secondaryText)
            }
            .accessibilityLabel(Text("关闭"))
            .accessibilityIdentifier("heatmapCloseButton")
        }
    }

    private var yearMenu: some View {
        Menu {
            ForEach(HeatmapYearRange.availableYears.reversed(), id: \.self) { year in
                Button("\(year)") { handleSelectYear(year) }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(heatmapModel.year)")
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
                .foregroundStyle(SemanticColor.secondaryText)
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
        timelineModel.heatmapFocusDate = nil
    }

    /// 点格定位：日锚点取当天最新一条——传入当天 23:59:59，`TimelineQuery.scrollTargetID`
    /// 据此挑出「occurredAt <= 当天末刻」中最大的一条，即当天最晚记录（见阶段5计划决策4、
    /// `TimelineQuery` 头部说明）；再次点击同一天 → `heatmapFocusDate = nil` 取消定位
    /// （不主动滚动、不撤销已发生的滚动位置，只清高亮，见 04 §4.3）。
    private func handleSelectDay(_ date: Date) {
        let calendar = Calendar.current
        if let current = timelineModel.heatmapFocusDate, calendar.isDate(current, inSameDayAs: date) {
            timelineModel.heatmapFocusDate = nil
            return
        }
        guard let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date) else {
            assertionFailure("日期锚点合成失败：\(date)")
            return
        }
        timelineModel.heatmapFocusDate = endOfDay
    }
}

#Preview {
    // swiftlint:disable:next force_try
    YearHeatmapView(modelContainer: try! ModelContainerConfig.makeInMemoryContainer())
        .environment(AppRouter())
        .environment(TimelineModel())
        .environment(ThemeManager())
}
