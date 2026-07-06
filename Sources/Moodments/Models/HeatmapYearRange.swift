import Foundation

/// 年度回看候选年份——热力图年份选择器（`YearHeatmapView`）与心情统计年份选择器
/// （`MoodStatsView`）共用同一份来源（阶段5 review 修复：此前 `MoodStatsView.availableYears`
/// 写死 `2021...2026` 且被 `YearHeatmapView` 反向引用，跨 2026 年后当前年份不在候选内）。
///
/// 中立共享位置：不挂在任一 feature 视图上，与 `Quota` 同类——全 App 的唯一权威定义。
enum HeatmapYearRange {
    /// App 最早可回看年份（产品既定起点）。
    private static let earliestYear = 2021

    /// 当前可选年份区间：`earliestYear...当前年`（升序）。每次访问按 `Calendar.current` 现算
    /// 当前年份，不缓存跨年边界，天然支持跨元旦无需改代码；纯函数、无共享可变状态，
    /// Swift 6 严格并发下可从任意隔离域安全访问。
    static var availableYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: .now)
        return Array(earliestYear...currentYear)
    }
}
