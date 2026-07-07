/// 时间轴轨道结构层的可见性合同。
///
/// 轨道只在存在阅读单元时出现。筛选空态没有任何日期、心情节点或气泡可挂载，
/// 因此不应渲染 lead-in、记录行轨道或底部 overshoot。
struct TimelineRailVisibility: Equatable {
    let showsRailRows: Bool

    static func resolve(visibleReadingUnitCount: Int, isFilteredEmpty: Bool) -> Self {
        TimelineRailVisibility(
            showsRailRows: !isFilteredEmpty && visibleReadingUnitCount > 0
        )
    }
}
