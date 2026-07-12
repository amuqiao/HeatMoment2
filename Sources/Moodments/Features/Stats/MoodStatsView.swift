import SwiftUI

/// 心情统计页（见 `docs/design/04-screen-specs.md` §4.12）：顶栏「‹设置 | 年份」+ 卡片1
/// 「心情日期分布」热力图 + 卡片2「心情统计」8 情绪条形；设置栈内 `NavigationLink` push
/// （见 08-architecture.md §2.2），**不定位时间轴、不接 `activeFilter`**（独立全量，见
/// `MoodStatsModel` 头部注释）。
struct MoodStatsView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(CanonicalLibraryService.self) private var canonicalService
    @State private var model: MoodStatsModel

    private struct LoadKey: Equatable {
        let year: Int
        let changeToken: Int
    }

    init(canonicalService: CanonicalLibraryService) {
        _model = State(initialValue: MoodStatsModel(canonicalService: canonicalService))
    }

    var body: some View {
        ScrollView {
            TaskResponsiveContent(spacing: 24) {
                heatmapCard
                barsCard
            }
        }
        .background(theme.canvasBackground.ignoresSafeArea())
        .appSheetDetailNavigationChrome("心情统计")
        .themedTaskContainer(theme)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                yearPicker
            }
        }
        .task(id: LoadKey(year: model.year, changeToken: canonicalService.changeToken)) {
            do {
                try await model.load()
            } catch {
                assertionFailure("心情统计加载失败：\(error)")
            }
        }
    }

    private var yearPicker: some View {
        Menu {
            ForEach(model.availableYears.reversed(), id: \.self) { year in
                Button {
                    model.year = year
                } label: {
                    Text(verbatim: String(year))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: String(model.year))
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(theme.accent.opacity(0.14))
            )
        }
        .accessibilityIdentifier("moodStatsYearPicker")
        .accessibilityLabel(Text("年份，\(String(model.year))"))
        .accessibilityAdjustableAction { direction in
            let years = model.availableYears
            guard let index = years.firstIndex(of: model.year) else { return }
            switch direction {
            case .increment where index + 1 < years.count:
                model.year = years[index + 1]
            case .decrement where index > 0:
                model.year = years[index - 1]
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
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(theme.bubbleBackground))
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
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(theme.bubbleBackground))
        // 注：不在卡片容器上叠加 `.accessibilityIdentifier`——会覆盖 `MoodStatBarView` 各条形
        // 自己的 identifier（见 `FilterPanelView` 同类教训，登记于 `YearHeatmapView`）。
    }
}

#Preview {
    NavigationStack {
        // swiftlint:disable:next force_try
        let canonicalService = try! CanonicalLibraryService(runtime: .makeInMemoryForTests())
        MoodStatsView(canonicalService: canonicalService)
            .environment(ThemeManager())
            .environment(canonicalService)
    }
}
