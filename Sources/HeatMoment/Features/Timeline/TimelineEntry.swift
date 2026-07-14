import Foundation

/// 时间轴一行的 canonical Moment value projection。
///
/// `TimelineRowView` 只消费这个投影对象，不直接持有 GRDB row。这样时间轴 viewport、
/// 滚动定位、左滑删除动画和行样式只依赖稳定值；写入副作用和预览路由通过 `momentID`
/// 回到 canonical 数据层，避免 live storage 引用渗入阅读单元。
struct TimelineEntry: Identifiable, Equatable {
    let id: UUID
    let momentID: UUID?
    let title: String
    let bodyText: String
    let mood: Mood
    let occurredAt: Date
    let tagNames: [String]
    let imageIDs: [UUID]

    /// 无障碍朗读文案（见 docs/current/implementation-truth.md §4.1：「5月17日 17:06，心情开心，标题《XXX》」）。
    var accessibilityLabel: String {
        let dateText = Self.accessibilityDateFormatter.string(from: occurredAt)
        return LanguagePreference.localizedString("\(dateText)，心情\(mood.displayName)，标题《\(title)》")
    }

    /// 无障碍朗读日期格式化器缓存：避免逐行、逐次求值重建（DateFormatter 构造昂贵）。
    private static let accessibilityDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}
