import Foundation

/// 筛选命中判定（纯函数）：多标签 AND 交集 + 心情单选，两个维度之间也是 AND
/// （见 `docs/design/04-screen-specs.md` §4.2「筛选组合逻辑」、`docs/design/13-open-questions.md` #19）。
///
/// 与 `TimelineQuery.predicate(for:)` 分工：`@Query` 谓词只能可靠表达 `deletedFlag` + `mood`
/// （见 `docs/plans/implementation-plan.md` 阶段 5 计划），标签 AND 交集在内存用本函数判定；
/// 也被 `MomentRepository.moodByDay(year:filter:)` 复用，保证「时间轴内存过滤」与「热力图聚合过滤」
/// 走同一套命中逻辑，不各自实现一遍造成漂移。
extension FilterCondition {
    /// - Parameters:
    ///   - tagIDs: 该条时刻已挂的全部标签 id。
    ///   - mood: 该条时刻的情绪。
    /// - Returns: 是否命中本筛选条件——需同时满足「已挂标签集合包含全部选中标签」（若选了标签）
    ///   与「情绪等于所选心情」（若选了心情）。未选任何条件（`isEmpty`）恒命中。
    func matches(tagIDs: Set<UUID>, mood: Mood) -> Bool {
        if !self.tagIDs.isEmpty, !self.tagIDs.isSubset(of: tagIDs) {
            return false
        }
        if let requiredMood = self.mood, requiredMood != mood {
            return false
        }
        return true
    }
}
