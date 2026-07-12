import SwiftUI

/// 时间轴一行：日期列 + 心情节点（按该条情绪的心情色着色）+ 气泡卡片（见 docs/current/implementation-truth.md §5.5）。
/// 预置引导 Moment 不可点、不可删（`isGuided`），真实 Moment 点击弹出预览阅读卡片
/// （见 docs/current/implementation-truth.md §4.1/§4.14）、左滑露出删除动作（软删除进垃圾箱）。
///
/// **架构边界**：连续时间轴轨道是稳定骨架；日期、心情节点和气泡是同一条 Moment 的阅读单元。
/// 左滑删除使用 SwiftUI `List` 行的成熟 `.swipeActions` 语义；独立轨道层不进入可滑动内容。
/// 轨道位于 `TimelineViewportView` 的场景层，阅读单元位于行前景，二者消费同一个
/// `TimelineGeometry` 坐标契约。
struct TimelineRowView: View {
    let entry: TimelineEntry
    let geometry: TimelineGeometry
    let style: TimelineSceneStyle
    let onTap: () -> Void
    var onDelete: (() -> Void)?

    private var deleteAction: (() -> Void)? {
        entry.isGuided ? nil : onDelete
    }

    var body: some View {
        VStack(spacing: 0) {
            TimelineReadingUnitView(
                entry: entry,
                geometry: geometry,
                style: style,
                onTap: onTap
            )

            // 行间距只负责阅读节奏；连续轨道由 viewport 场景层统一绘制。
            Color.clear.frame(height: geometry.rowGapHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(entry.accessibilityLabel))
        .accessibilityAddTraits(entry.isGuided ? [] : .isButton)
        .modifier(
            TimelineRowActivateAccessibilityModifier(
                isEnabled: !entry.isGuided,
                onActivate: onTap
            )
        )
        .modifier(TimelineDeleteSwipeActionModifier(onDelete: deleteAction))
    }
}

private struct TimelineReadingUnitView: View {
    let entry: TimelineEntry
    let geometry: TimelineGeometry
    let style: TimelineSceneStyle
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: geometry.interColumnSpacing) {
            TimelineDateColumn(entry: entry, geometry: geometry, style: style.dateStamp)
            TimelineMoodAnchorColumn(mood: entry.mood, geometry: geometry, style: style.node)
            BubbleCardView(
                title: entry.title,
                bodyText: entry.bodyText,
                tagNames: entry.tagNames,
                placeholderImageHexColors: entry.placeholderImageHexColors,
                imageIDs: entry.imageIDs,
                tailCenterY: geometry.bubbleTailCenterY,
                tailGeometry: geometry.bubbleTailGeometry,
                style: style.bubble
            )
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !entry.isGuided else { return }
                onTap()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 时间轴结构层的日期说明。它不承担预览、删除或导航行为。
private struct TimelineDateColumn: View {
    let entry: TimelineEntry
    let geometry: TimelineGeometry
    let style: TimelineDateStampStyle

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: style.verticalSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: style.monthSpacing) {
                Text(dayText).font(style.dayFont)
                Text(monthText).font(style.monthFont)
            }
            .foregroundStyle(theme.primaryText)

            Text(timeText)
                .font(style.timeFont)
                .foregroundStyle(theme.bubbleBodyText)
        }
        .frame(width: geometry.dateColumnWidth, alignment: .leading)
    }

    private var dayText: String {
        String(Calendar.current.component(.day, from: entry.occurredAt))
    }

    private var monthText: String {
        "\(Calendar.current.component(.month, from: entry.occurredAt))月"
    }

    private var timeText: String {
        Self.timeFormatter.string(from: entry.occurredAt)
    }

    /// 24 小时制时间格式化器缓存：`DateFormatter` 构造昂贵，避免逐行、逐次 body 求值重建。
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

/// 时间轴结构层的情绪锚点。轨道由 viewport 场景层绘制，这里只负责节点本身。
private struct TimelineMoodAnchorColumn: View {
    let mood: Mood
    let geometry: TimelineGeometry
    let style: TimelineMoodNodeStyle

    var body: some View {
        MoodNodeView(mood: mood, diameter: geometry.nodeDiameter, style: style)
            .padding(.top, geometry.nodeTopPadding)
            .frame(width: geometry.nodeColumnWidth, alignment: .top)
    }
}

/// 真实 Moment 的 VoiceOver 默认动作：和点击气泡一致，打开预览阅读卡片。
private struct TimelineRowActivateAccessibilityModifier: ViewModifier {
    let isEnabled: Bool
    let onActivate: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.accessibilityAction { onActivate() }
        } else {
            content
        }
    }
}

/// 左滑删除动作 + 无障碍替代路径（见 docs/current/implementation-truth.md §4.1：首页删除无需二次确认，
/// 有垃圾箱兜底，见公理3）。`onDelete == nil` 时不挂行操作（引导 Moment 不可删）。
private struct TimelineDeleteSwipeActionModifier: ViewModifier {
    let onDelete: (() -> Void)?

    func body(content: Content) -> some View {
        if let onDelete {
            content
                .destructiveSwipeAction(
                    title: "删除",
                    accessibilityIdentifier: "timelineSwipeDeleteButton",
                    action: onDelete
                )
        } else {
            content
        }
    }
}
