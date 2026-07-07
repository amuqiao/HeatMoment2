import Foundation
import Observation
import SwiftData

/// 首页热力图顶部上下文区局部状态（见 `docs/design/04-screen-specs.md` §4.3）：年份选择 + 当前年度
/// 的日期→心情聚合数据。
///
/// **接 `TimelineModel.activeFilter` 口径**（见 `docs/plans/implementation-plan.md` 阶段5决策1：
/// 「热力图接 `activeFilter`；`MoodStatsView` 不接」）：聚合时把当前筛选条件传给
/// `MomentRepository.moodByDay(year:filter:)`，但这只是换了一批要聚合展示的数据源，不改变
/// 热力图本身「点格只改变滚动位置」的定位语义，不违反公理2（见 `TimelineModel` 头部注释）。
@MainActor
@Observable
final class YearHeatmapModel {
    var year: Int
    var moodByDay: [Int: Mood] = [:]

    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer, year: Int = Calendar.current.component(.year, from: .now)) {
        self.modelContainer = modelContainer
        self.year = year
    }

    /// 供 `.task(id:)` 调用：按当前 `year` + 传入的 `filter` 重新聚合（后台 `ModelActor`，
    /// 跨隔离域只回传 `[Int: Mood]` 值类型，见 08-architecture.md §5）。
    func load(filter: FilterCondition?) async throws {
        let repository = MomentRepository(modelContainer: modelContainer)
        moodByDay = try await repository.moodByDay(year: year, filter: filter)
    }
}
