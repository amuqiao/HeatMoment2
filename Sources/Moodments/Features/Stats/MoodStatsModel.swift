import Foundation
import Observation
import SwiftData

/// 心情统计页局部状态（见 `docs/design/04-screen-specs.md` §4.12）：与首页时间轴的
/// `TimelineModel` 完全独立——**不接 `activeFilter`、不接 `heatmapFocusDate`**，年份切换只刷新
/// 本页两个卡片的全量数据，不影响、也不读取时间轴的筛选/定位状态（见 04 §4.12「卡片1不承担
/// 定位时间轴功能...与首页 `YearHeatmapView` 是两个独立组件」）。
@MainActor
@Observable
final class MoodStatsModel {
    var year: Int
    var availableYears: [Int]
    var moodByDay: [Int: Mood] = [:]
    var moodCounts: [Mood: Int] = [:]

    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer, year: Int = HeatmapYearRange.currentYear) {
        self.modelContainer = modelContainer
        self.year = year
        availableYears = [year]
    }

    /// 供 `.task(id: model.year)` 调用：按当前 `year` 重新加载两个卡片的数据（均为全量，无筛选）。
    func load() async throws {
        let repository = MomentRepository(modelContainer: modelContainer)
        availableYears = try await repository.availableYears()
        if !availableYears.contains(year) {
            year = HeatmapYearRange.currentYear
        }
        moodByDay = try await repository.moodByDay(year: year, filter: nil)
        moodCounts = try await repository.moodCounts(year: year)
    }
}
