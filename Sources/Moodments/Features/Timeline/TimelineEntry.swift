import Foundation

/// 时间轴一行的 value projection，统一「真实 Moment」与「预置引导 Moment」两种来源
/// （见 02-information-architecture.md 空态引导、04-screen-specs.md §4.1）。
///
/// `TimelineRowView` 只消费这个投影对象，不直接持有 SwiftData `Moment`。这样时间轴 viewport、
/// 滚动定位、左滑删除动画和行样式只依赖稳定值；SwiftData 刷新、软删除副作用和预览路由通过
/// `momentID` 回到数据层，避免 live model 引用渗入阅读单元。
struct TimelineEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case real
        case guided
    }

    let id: UUID
    let momentID: UUID?
    let kind: Kind
    let title: String
    let bodyText: String
    let mood: Mood
    let occurredAt: Date
    let tagNames: [String]
    let placeholderImageHexColors: [UInt32]
    let imageIDs: [UUID]

    /// 真实 Moment 投影：只抽取渲染与交互必要值，不把 `Moment` 本体传入行视图。
    static func real(_ moment: Moment) -> TimelineEntry {
        TimelineEntry(
            id: moment.id,
            momentID: moment.id,
            kind: .real,
            title: moment.title,
            bodyText: moment.bodyText,
            mood: moment.mood,
            occurredAt: moment.occurredAt,
            tagNames: moment.tags.map(\.name),
            placeholderImageHexColors: [],
            imageIDs: moment.images.sorted { $0.sortIndex < $1.sortIndex }.map(\.id)
        )
    }

    /// 预置引导 Moment 投影：不可点、不可删，仅用于空数据态的阅读引导。
    static func guided(_ guided: GuidedMoment) -> TimelineEntry {
        TimelineEntry(
            id: guided.id,
            momentID: nil,
            kind: .guided,
            title: guided.title,
            bodyText: guided.bodyText,
            mood: guided.mood,
            occurredAt: guided.occurredAt,
            tagNames: [],
            placeholderImageHexColors: guided.placeholderImageHexColors,
            imageIDs: []
        )
    }

    /// 预置引导 Moment 不可删/不可编辑/不可点开预览（见 02-information-architecture.md）。
    var isGuided: Bool { kind == .guided }

    /// 无障碍朗读文案（见 04-screen-specs.md §4.1：「5月17日 17:06，心情开心，标题《XXX》」）。
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
