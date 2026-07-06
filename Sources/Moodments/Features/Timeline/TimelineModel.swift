import Foundation
import Observation

/// 首页时间轴的局部状态（见 08-architecture.md §4.1/§4.2）。
///
/// **热力图定位 `heatmapFocusDate` 与筛选 `activeFilter` 必须是两个独立状态源，严禁合并**——
/// 依 `product-mental-model.md` 公理2「定位 ≠ 筛选」：定位只改变滚动位置（不改变可见数据集合），
/// 筛选只改变可见数据集合（不改变滚动逻辑），二者正交、可同时存在。
///
/// 阶段5起接真实交互：`TimelineListView` 的 `@Query` 谓词消费 `activeFilter`
/// （见 `TimelineQuery.predicate(for:)`），`heatmapFocusDate` 驱动 `ScrollViewReader` 滚动
/// （见 `TimelineQuery.scrollTargetID(for:in:)`）；两者互不引用、互不覆盖。
///
/// **上提**（阶段5必要重构）：本类型由 `RootView` 持有并通过 `.environment()` 注入整棵树
/// （含 `TimelineHomeView` 与热力图覆盖层 `YearHeatmapView`），使时间轴与热力图共享同一实例——
/// 热力图写入 `heatmapFocusDate`、读取 `activeFilter` 决定聚合口径，都必须与时间轴看到的是
/// 同一份状态，而不是两份互不相干的拷贝。
@MainActor
@Observable
final class TimelineModel {
    /// 热力图定位锚点：仅用于驱动 `ScrollViewReader` 滚动目标，绝不影响 `@Query` 谓词（公理2）。
    var heatmapFocusDate: Date?

    /// 标签/心情筛选条件：仅用于影响 `@Query` 谓词，绝不影响滚动逻辑（公理2）。
    var activeFilter: FilterCondition?

    init() {}

    /// 派生只读：当前是否处于定位态（上下文标记横条、行高亮据此显示，见 04-screen-specs.md §4.1）。
    /// 只读取 `heatmapFocusDate`，不新增独立存储、不与 `activeFilter`耦合。
    var isLocated: Bool { heatmapFocusDate != nil }

    /// 派生只读：当前是否处于筛选态。只读取 `activeFilter`，不新增独立存储。
    var hasFilter: Bool { !(activeFilter?.isEmpty ?? true) }
}
