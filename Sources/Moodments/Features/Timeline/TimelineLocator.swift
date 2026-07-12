import Foundation

/// 时间轴定位的纯函数集合。
///
/// 公理2「定位 ≠ 筛选」：本类型只在调用方已经算好的「当前可见（已筛选）集」里挑一个
/// 滚动目标 id，既不返回、也不修改数据集本身。
enum TimelineLocator {
    /// 从「当前可见（已筛选）集」`entries` 中，挑选定位应滚动到的锚点 id。
    ///
    /// 调用方决定 `date` 的粒度以实现「月/日」定位语义（见 docs/current/implementation-truth.md §4.3、
    /// docs/plans/README.md 相关裁决）：传入某日 23:59:59 定位到该日最新一条；
    /// 传入某月最后一刻定位到该月最新一条。找不到同一天/同一月的条目时返回 `nil`，
    /// 不能退到更早月份或更早日期，否则会破坏「点的是哪个时间位置」的上下文语义。
    ///
    /// 本函数只读 `entries`、只返回一个 `UUID?`，**不返回、不修改数据集合本身**——
    /// 数据集合是否包含哪些条目完全由调用方查询条件决定，与本函数无关。
    static func scrollTargetID(
        for date: Date,
        granularity: HeatmapAnchorGranularity = .day,
        in entries: [TimelineEntry]
    ) -> UUID? {
        let calendar = Calendar.current
        return
            entries
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
