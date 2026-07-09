import Foundation

/// 年度回看的默认年份工具。可选年份列表不再固定为时间窗口，而是由
/// `MomentRepository.availableYears(includingCurrentYear:)` 按未删除记录的发生年份派生，
/// 并合并当前年；这里仅保留“当前年”这一无记录空态默认值的单一来源。
enum HeatmapYearRange {
    /// 当前年份：每次访问按 `Calendar.current` 现算，不缓存跨年边界。
    static var currentYear: Int {
        Calendar.current.component(.year, from: .now)
    }
}
