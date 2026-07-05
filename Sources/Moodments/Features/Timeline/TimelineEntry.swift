import Foundation

/// 时间轴一行的展示数据，统一「真实 Moment」与「预置引导 Moment」两种来源
/// （见 02-information-architecture.md 空态引导、04-screen-specs.md §4.1）。
///
/// 只在 `TimelineHomeView` 所在的 `@MainActor` 视图内使用，不跨隔离域传递
/// （`.real` 分支持有 `Moment` 引用，遵循「@Query 直接驱动列表」的既定架构，见
/// 08-architecture.md §4.1；不用于传给后台 `ModelActor`）。
enum TimelineEntry: Identifiable {
    case real(Moment)
    case guided(GuidedMoment)

    var id: UUID {
        switch self {
        case let .real(moment): moment.id
        case let .guided(guided): guided.id
        }
    }

    var title: String {
        switch self {
        case let .real(moment): moment.title
        case let .guided(guided): guided.title
        }
    }

    var bodyText: String {
        switch self {
        case let .real(moment): moment.bodyText
        case let .guided(guided): guided.bodyText
        }
    }

    var mood: Mood {
        switch self {
        case let .real(moment): moment.mood
        case let .guided(guided): guided.mood
        }
    }

    var occurredAt: Date {
        switch self {
        case let .real(moment): moment.occurredAt
        case let .guided(guided): guided.occurredAt
        }
    }

    var tagNames: [String] {
        switch self {
        case let .real(moment): moment.tags.map(\.name)
        case .guided: []
        }
    }

    /// 阶段 2 真实 Moment 尚无图片渲染（编辑器/照片入库见阶段3），故恒为空；
    /// 预置引导 Moment 用固定占位色块模拟图片区（见 `GuidedMoment`）。
    var placeholderImageHexColors: [UInt32] {
        switch self {
        case .real: []
        case let .guided(guided): guided.placeholderImageHexColors
        }
    }

    /// 预置引导 Moment 不可删/不可编辑/不可点开预览（见 02-information-architecture.md）。
    var isGuided: Bool {
        if case .guided = self { true } else { false }
    }

    /// 无障碍朗读文案（见 04-screen-specs.md §4.1：「5月17日 17:06，心情开心，标题《XXX》」）。
    var accessibilityLabel: String {
        let dateText = Self.accessibilityDateFormatter.string(from: occurredAt)
        return "\(dateText)，心情\(mood.displayName)，标题《\(title)》"
    }

    /// 无障碍朗读日期格式化器缓存：避免逐行、逐次求值重建（DateFormatter 构造昂贵）。
    private static let accessibilityDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}
