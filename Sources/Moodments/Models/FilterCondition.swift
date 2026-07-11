import Foundation

/// 筛选条件值类型——时间轴的标签/心情筛选（就近浮窗）产出的当前条件。
///
/// 语义（已裁决，见 `docs/design/04-screen-specs.md` §「筛选组合逻辑」与
/// `docs/design/13-open-questions.md` #19）：
/// - 标签**可多选**，选中的多个标签之间按 **AND（交集）**：一条时刻必须同时挂有全部选中标签才命中；
/// - 心情**单选**（一次一个）；
/// - 标签维度与心情维度之间也是 AND：最终命中条件 = （含全部选中标签）且（命中所选心情，若选了）。
///
/// 只传值类型跨隔离域使用：标签用 canonical tag id（`UUID`），不传 storage row 引用。
struct FilterCondition: Sendable, Equatable {
    /// 选中的标签 id 集合，彼此 AND（交集）；为空表示不按标签筛选。
    var tagIDs: Set<UUID>

    /// 选中的心情，单选；`nil` 表示不按心情筛选。
    var mood: Mood?

    init(tagIDs: Set<UUID> = [], mood: Mood? = nil) {
        self.tagIDs = tagIDs
        self.mood = mood
    }

    /// 当前条件是否等价于「无筛选」（标签为空且未选心情）。
    var isEmpty: Bool { tagIDs.isEmpty && mood == nil }
}
