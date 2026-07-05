import Foundation
import Observation

/// 首页时间轴的局部状态（见 08-architecture.md §4.1/§4.2）。
///
/// **热力图定位 `heatmapFocusDate` 与筛选 `activeFilter` 必须是两个独立状态源，严禁合并**——
/// 依 `product-mental-model.md` 公理2「定位 ≠ 筛选」：定位只改变滚动位置（不改变可见数据集合），
/// 筛选只改变可见数据集合（不改变滚动逻辑），二者正交、可同时存在。
///
/// 阶段 2 仅建立状态占位：不接入真正的定位滚动逻辑（阶段5）、不接入真实筛选谓词（阶段5）；
/// `TimelineHomeView` 当前的 `@Query` 谓词固定为「未删除、按发生时间倒序」，尚未消费 `activeFilter`。
@MainActor
@Observable
final class TimelineModel {
    /// 热力图定位锚点：仅用于驱动 `ScrollViewReader` 滚动目标，绝不影响 `@Query` 谓词（公理2）。
    var heatmapFocusDate: Date?

    /// 标签/心情筛选条件：仅用于影响 `@Query` 谓词，绝不影响滚动逻辑（公理2）。
    /// 由阶段5的 `FilterPanelView` 回填真实交互；阶段2 仅占位。
    var activeFilter: FilterCondition?

    init() {}
}
