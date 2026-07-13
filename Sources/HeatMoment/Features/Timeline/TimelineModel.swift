import Foundation
import Observation

/// 首页时间轴的局部状态（见 docs/current/implementation-truth.md §4.1/§4.2）。
///
enum HeatmapAnchorGranularity: Equatable {
    case day
    case month
}

/// **热力图定位 `heatmapFocusDate` 与筛选 `activeFilter` 必须是两个独立状态源，严禁合并**——
/// 依 `product-mental-model.md` 公理2「定位 ≠ 筛选」：定位只改变滚动位置（不改变可见数据集合），
/// 筛选只改变可见数据集合（不改变滚动逻辑），二者正交、可同时存在。
///
/// 主流程切到 canonical 后，`TimelineViewportView` 用 `activeFilter` 重新加载可见集；
/// `heatmapFocusDate` 只驱动 `ScrollViewReader` 滚动（见
/// `TimelineLocator.scrollTargetID(for:granularity:in:)`）；两者互不引用、互不覆盖。
///
/// **上提**（阶段5必要重构）：本类型由 `RootView` 持有并通过 `.environment()` 注入整棵树
/// （含 `TimelineHomeView` 与热力图顶部上下文区 `YearHeatmapView`），使时间轴与热力图共享同一实例——
/// 热力图写入 `heatmapFocusDate`、读取 `activeFilter` 决定聚合口径，都必须与时间轴看到的是
/// 同一份状态，而不是两份互不相干的拷贝。
@MainActor
@Observable
final class TimelineModel {
    /// 主时间轴内容版本：只表达「未删除 Moment 集合或排序/聚合关键字段发生变化」。
    /// 首页热力图等派生视图把它纳入 `.task(id:)`，从 canonical 真相源重新计算年度候选
    /// 和聚合数据；它不携带筛选/定位语义，避免把「定位 ≠ 筛选」重新耦合。
    var timelineContentRevision = 0

    /// 热力图定位锚点：仅用于驱动 `ScrollViewReader` 滚动目标，绝不影响资料库筛选条件（公理2）。
    var heatmapFocusDate: Date? {
        didSet {
            if heatmapFocusDate == nil {
                heatmapAnchorGranularity = nil
            } else if heatmapAnchorGranularity == nil {
                heatmapAnchorGranularity = .day
            }
        }
    }

    /// 当前热力图锚点粒度。旧代码直接写 `heatmapFocusDate` 时默认视为日期锚点；
    /// 月份选择必须通过 `setHeatmapAnchor(_:granularity:)` 写入，以保留月/日 UI 语义。
    var heatmapAnchorGranularity: HeatmapAnchorGranularity?

    /// 标签/心情筛选条件：仅用于影响 canonical 查询，绝不影响滚动逻辑（公理2）。
    var activeFilter: FilterCondition?

    init() {}

    func noteTimelineContentChanged() {
        timelineContentRevision += 1
    }

    /// 派生只读：当前是否处于定位态（上下文标记横条、行高亮据此显示，见 docs/current/implementation-truth.md §4.1）。
    /// 只读取 `heatmapFocusDate`，不新增独立存储、不与 `activeFilter`耦合。
    var isLocated: Bool { heatmapFocusDate != nil }

    /// 派生只读：当前是否处于筛选态。只读取 `activeFilter`，不新增独立存储。
    var hasFilter: Bool { !(activeFilter?.isEmpty ?? true) }

    /// 标签删除后清理 `activeFilter` 中的陈旧 id（阶段6计划决策5，见
    /// `docs/plans/implementation-plan.md` 阶段6 §8「筛选中标签被删除后的陈旧标记」）：
    /// 从 `tagIDs` 中移除该 id；移除后标签与心情两个维度都为空则把 `activeFilter` 置 `nil`
    /// （回到「无筛选」态），**不触碰 `mood` 维度**——标签删除只影响标签维度（公理7「标签是
    /// 归类不是所有权」在筛选状态上的延伸：删标签不应连带清空用户选的心情筛选）。
    /// 若 `id` 不在当前筛选里（未筛选该标签、或已被清理过）则是无操作，不视为错误。
    func discardFilterTag(_ id: UUID) {
        guard var filter = activeFilter, filter.tagIDs.contains(id) else { return }
        filter.tagIDs.remove(id)
        activeFilter = filter.isEmpty ? nil : filter
    }

    func setHeatmapAnchor(_ date: Date, granularity: HeatmapAnchorGranularity) {
        heatmapAnchorGranularity = granularity
        heatmapFocusDate = date
    }

    func clearHeatmapAnchor() {
        heatmapFocusDate = nil
    }
}
