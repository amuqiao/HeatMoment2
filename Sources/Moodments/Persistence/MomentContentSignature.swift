import Foundation

/// 未删除 Moment 集合的轻量变化签名。派生视图用它观察本地 SwiftData 真相源变化，
/// 触发热力图/统计等聚合重新计算；签名只覆盖会影响年份候选、年度排序或聚合结果的字段。
struct MomentContentSignature: Equatable {
    let id: UUID
    let occurredAt: Date
    let updatedAt: Date

    init(moment: Moment) {
        id = moment.id
        occurredAt = moment.occurredAt
        updatedAt = moment.updatedAt
    }
}
