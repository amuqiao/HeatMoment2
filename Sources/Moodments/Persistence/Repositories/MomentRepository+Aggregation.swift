import Foundation
import SwiftData

/// 热力图 / 心情统计的年度聚合（见 `docs/design/04-screen-specs.md` §4.3/§4.12、
/// `docs/design/05-design-system.md` §5.4「心情色一致性」、`docs/plans/implementation-plan.md` 阶段5）。
///
/// 与 `MomentRepository` 主体一致：在后台 `ModelActor` 内取数，跨隔离域只回传值类型
/// （`[Int: Mood]` / `[Mood: Int]`，均 `Sendable`），不传 `@Model` 引用（见 08-architecture.md §5）。
extension MomentRepository {
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
        guard let interval = Self.yearInterval(year: year) else { return [:] }
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
        guard let interval = Self.yearInterval(year: year) else { return [:] }
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

    private static func yearInterval(year: Int) -> DateInterval? {
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        let calendar = Calendar.current
        guard let start = calendar.date(from: components) else { return nil }
        guard let end = calendar.date(byAdding: .year, value: 1, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }
}
