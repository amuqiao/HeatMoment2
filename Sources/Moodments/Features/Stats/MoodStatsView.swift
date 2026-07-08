import SwiftData
import SwiftUI

/// 心情统计页（见 `docs/design/04-screen-specs.md` §4.12）：顶栏「‹设置 | 年份」+ 卡片1
/// 「心情日期分布」热力图 + 卡片2「心情统计」8 情绪条形；设置栈内 `NavigationLink` push
/// （见 08-architecture.md §2.2），**不定位时间轴、不接 `activeFilter`**（独立全量，见
/// `MoodStatsModel` 头部注释）。
struct MoodStatsView: View {
    @Environment(ThemeManager.self) private var theme
    @State private var model: MoodStatsModel

    init(modelContainer: ModelContainer) {
        _model = State(initialValue: MoodStatsModel(modelContainer: modelContainer))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heatmapCard
                barsCard
            }
            .padding(20)
        }
        .background(theme.canvasBackground.ignoresSafeArea())
        .navigationTitle("心情统计")
        .themedTaskContainer(theme)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                yearPicker
            }
        }
        .task(id: model.year) {
            do {
                try await model.load()
            } catch {
                assertionFailure("心情统计加载失败：\(error)")
            }
        }
    }

    private var yearPicker: some View {
        Menu {
            ForEach(HeatmapYearRange.availableYears.reversed(), id: \.self) { year in
                Button("\(year)") { model.year = year }
            }
        } label: {
            HStack(spacing: 2) {
                Text("\(model.year)")
                Image(systemName: "chevron.up.chevron.down")
            }
            .foregroundStyle(theme.accent)
        }
        .accessibilityIdentifier("moodStatsYearPicker")
        .accessibilityLabel(Text("年份，\(model.year)"))
        .accessibilityAdjustableAction { direction in
            guard let index = HeatmapYearRange.availableYears.firstIndex(of: model.year) else { return }
            switch direction {
            case .increment where index + 1 < HeatmapYearRange.availableYears.count:
                model.year = HeatmapYearRange.availableYears[index + 1]
            case .decrement where index > 0:
                model.year = HeatmapYearRange.availableYears[index - 1]
            default:
                break
            }
        }
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("心情日期分布")
                .font(AppTypography.cardTitle)
                .foregroundStyle(theme.bubbleTitleText)
            HeatmapGridView(year: model.year, moodByDay: model.moodByDay)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(theme.bubbleBackground))
        // 注：不在卡片容器上叠加 `.accessibilityIdentifier`——会覆盖 `HeatmapGridView` 各日期格
        // 自己的 identifier（见 `FilterPanelView` 同类教训，登记于 `YearHeatmapView`）。
    }

    private var barsCard: some View {
        let total = model.moodCounts.values.reduce(0, +)
        return VStack(alignment: .leading, spacing: 16) {
            Text("心情统计")
                .font(AppTypography.cardTitle)
                .foregroundStyle(theme.bubbleTitleText)
            ForEach(Mood.allCases) { mood in
                MoodStatBarView(mood: mood, count: model.moodCounts[mood] ?? 0, totalCount: total)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(theme.bubbleBackground))
        // 注：不在卡片容器上叠加 `.accessibilityIdentifier`——会覆盖 `MoodStatBarView` 各条形
        // 自己的 identifier（见 `FilterPanelView` 同类教训，登记于 `YearHeatmapView`）。
    }
}

#Preview {
    NavigationStack {
        // swiftlint:disable:next force_try
        MoodStatsView(modelContainer: try! ModelContainerConfig.makeInMemoryContainer())
            .environment(ThemeManager())
    }
}
