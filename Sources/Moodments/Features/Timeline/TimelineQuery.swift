import Foundation
import SwiftData

/// 时间轴查询/定位的纯函数集合（见 `docs/plans/implementation-plan.md` 阶段5「正交性的结构保证」）。
///
/// **公理2「定位 ≠ 筛选」的类型层保证**：`predicate(for:)` 签名内**没有任何 `Date` 参数**——
/// 类型系统本身就杜绝了热力图定位污染数据集的可能；`scrollTargetID(for:granularity:in:)` 是纯函数，
/// 只在调用方已经算好的「当前可见（已筛选）集」里挑一个 id，既不返回、也不修改数据集本身。
/// 两个函数彼此不引用、不共享任何中间状态，`TimelineListView` 里也分别独立驱动
/// （`@Query` = f(filter)；`.onChange(of: locateScrollRequest)` = f(focusDate, granularity, entries)）。
enum TimelineQuery {
    /// 时间轴 `@Query` 谓词：只表达「未软删除」+「心情单选命中（若选了）」。
    ///
    /// **不放标签**：SwiftData `#Predicate` 对「集合是否包含某个子集」这类多值 AND 交集判断
    /// 不能可靠表达（`Tag` 是多对多关系），标签 AND 交集改在内存用 `FilterCondition.matches`
    /// 判定（见 `TimelineListView`）；本函数只负责「谓词层能可靠表达」的部分。
    ///
    /// **不接受 `Date` 参数**：热力图定位 `heatmapFocusDate` 绝不能进入这条谓词，签名上直接杜绝。
    static func predicate(for filter: FilterCondition?) -> Predicate<Moment> {
        guard let moodRawValue = filter?.mood?.rawValue else {
            return #Predicate<Moment> { $0.deletedFlag == false }
        }
        return #Predicate<Moment> { $0.deletedFlag == false && $0.moodRawValue == moodRawValue }
    }

    /// 从「当前可见（已筛选）集」`entries` 中，挑选定位应滚动到的锚点 id。
    ///
    /// 调用方决定 `date` 的粒度以实现「月/日」定位语义（见 04-screen-specs.md §4.3、
    /// 13-open-questions.md 相关裁决）：传入某日 23:59:59 定位到该日最新一条；
    /// 传入某月最后一刻定位到该月最新一条。找不到同一天/同一月的条目时返回 `nil`，
    /// 不能退到更早月份或更早日期，否则会破坏「点的是哪个时间位置」的上下文语义。
    ///
    /// 本函数只读 `entries`、只返回一个 `UUID?`，**不返回、不修改数据集合本身**——
    /// 数据集合是否包含哪些条目完全由 `predicate(for:)` 决定，与本函数无关。
    static func scrollTargetID(
        for date: Date,
        granularity: HeatmapAnchorGranularity = .day,
        in entries: [TimelineEntry]
    ) -> UUID? {
        let calendar = Calendar.current
        return entries
            .filter { entry in
                guard entry.momentID != nil else { return false }
                guard entry.occurredAt <= date else { return false }
                switch granularity {
                case .day:
                    return calendar.isDate(entry.occurredAt, inSameDayAs: date)
                case .month:
                    return calendar.isDate(entry.occurredAt, equalTo: date, toGranularity: .month)
                }
            }
            .max { $0.occurredAt < $1.occurredAt }?
            .id
    }
}
