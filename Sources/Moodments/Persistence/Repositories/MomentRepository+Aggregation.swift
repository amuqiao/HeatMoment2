import Foundation
import SwiftData

/// 热力图 / 心情统计的年度聚合（见 `docs/design/04-screen-specs.md` §4.3/§4.12、
/// `docs/design/05-design-system.md` §5.4「心情色一致性」、`docs/plans/implementation-plan.md` 阶段5）。
///
/// 与 `MomentRepository` 主体一致：在后台 `ModelActor` 内取数，跨隔离域只回传值类型
/// （`[Int: Mood]` / `[Mood: Int]`，均 `Sendable`），不传 `@Model` 引用（见 08-architecture.md §5）。
extension MomentRepository {
    /// 年份选择器候选：来自所有未软删除时刻的 `occurredAt` 年份，并强制合并当前年。
    /// 无记录时返回 `[currentYear]`，避免年份菜单为空。软删除记录不参与，因为热力图和统计页
    /// 的年度聚合也只展示主时间轴内的未删除记录。
    func availableYears(
        includingCurrentYear currentYear: Int = HeatmapYearRange.currentYear
    ) throws -> [Int] {
        let descriptor = FetchDescriptor<Moment>(
            predicate: #Predicate<Moment> { moment in
                moment.deletedFlag == false
            },
            sortBy: [SortDescriptor(\.occurredAt, order: .forward)]
        )
        let calendar = Calendar.current
        var years = Set<Int>()
        years.insert(currentYear)
        for moment in try modelContext.fetch(descriptor) {
            years.insert(calendar.component(.year, from: moment.occurredAt))
        }
        return years.sorted()
    }

    /// 年度「日期 → 当天最后一条时刻的心情」聚合（依公理1心情色一致性：热力图日期格用
    /// 当天最后一条时刻的心情色）。key 为 `dayOfYear`（`Calendar.ordinality(of:.day, in:.year, for:)`，
    /// 1...365/366）。
    ///
    /// - Parameter filter: 首页热力图跟随当前筛选口径时传入（见 04 §4.3「与筛选正交」：
    ///   热力图只统计「当前条件下」的年度分布，但这只是**换了一批数据源**，不改变热力图
    ///   本身「定位=滚动位置」的语义，不违反公理2）；`MoodStatsView` 传 `nil`（独立全量，见 04 §4.12）。
    ///   标签 AND 交集用 `FilterCondition.matches` 在内存判定（谓词层只能可靠过滤到年份区间 +
    ///   未软删除，见 `TimelineQuery.predicate(for:)` 同类取舍）。
    func moodByDay(year: Int, filter: FilterCondition?) throws -> [Int: Mood] {
        let interval = Self.yearInterval(year: year)
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<Moment>(
            predicate: #Predicate<Moment> { moment in
                moment.deletedFlag == false && moment.occurredAt >= start && moment.occurredAt < end
            },
            sortBy: [SortDescriptor(\.occurredAt, order: .forward)]
        )
        let moments = try modelContext.fetch(descriptor)
        let calendar = Calendar.current
        var result: [Int: Mood] = [:]
        for moment in moments {
            if let filter, !filter.matches(tagIDs: Set(moment.tags.map(\.id)), mood: moment.mood) {
                continue
            }
            guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: moment.occurredAt) else {
                // 记录已确定落在 `[start, end)` 年份区间内，`ordinality` 理论上不应返回 nil；
                // 一旦出现即为不可预期的日历计算异常，快速暴露而非静默丢弃该记录
                // （见 CLAUDE.md 快速失败铁律，不加兜底）。
                assertionFailure("年内记录 dayOfYear 计算失败：\(moment.occurredAt)")
                continue
            }
            // 正序遍历，同一天后写入的时刻 occurredAt 更晚，天然覆盖成「当天最后一条」。
            result[dayOfYear] = moment.mood
        }
        return result
    }

    /// 年度「情绪 → 命中次数」聚合，供 `MoodStatsView` 8 情绪条形图使用；恒为全量、不接筛选
    /// （见 04-screen-specs.md §4.12：「卡片1不承担定位时间轴功能...仅视觉范式相似」）。
    func moodCounts(year: Int) throws -> [Mood: Int] {
        let interval = Self.yearInterval(year: year)
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<Moment>(
            predicate: #Predicate<Moment> { moment in
                moment.deletedFlag == false && moment.occurredAt >= start && moment.occurredAt < end
            }
        )
        let moments = try modelContext.fetch(descriptor)
        var counts: [Mood: Int] = [:]
        for moment in moments {
            counts[moment.mood, default: 0] += 1
        }
        return counts
    }

    /// 年份区间合成——对任何合法 `Int` 年份，`Calendar.date(from:)`/`date(byAdding:)` 不应失败；
    /// 一旦失败即为不可预期的日历计算异常，直接 `preconditionFailure` 崩溃暴露，不返回可选值
    /// 让调用方靠 `guard ... else { return [:] }` 静默降级（见 CLAUDE.md 快速失败铁律）。
    private static func yearInterval(year: Int) -> DateInterval {
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        let calendar = Calendar.current
        guard let start = calendar.date(from: components) else {
            preconditionFailure("年份起始日期合成失败：\(year)")
        }
        guard let end = calendar.date(byAdding: .year, value: 1, to: start) else {
            preconditionFailure("年份结束日期合成失败：\(year)")
        }
        return DateInterval(start: start, end: end)
    }
}
