import SwiftUI

/// 时间轴一行：日期列 + 心情节点（按该条情绪的心情色着色）+ 气泡卡片（见 05-design-system.md §5.5）。
/// 预置引导 Moment 不可点、不可删（`isGuided`），真实 Moment 点击弹出预览阅读卡片
/// （见 04-screen-specs.md §4.1）、左滑露出删除动作（软删除进垃圾箱，见 04 §4.14）。
///
/// **删除动作用成熟方案 `List` + `.swipeActions`**（`TimelineHomeView` 把本视图直接作为
/// `List` 行内容，`.swipeActions`/`.accessibilityAction` 挂在本视图的根容器上即对该行生效，
/// 见阶段 4 计划：禁止自定义 `DragGesture` 手搓滑动删除）；`onDelete` 为 `nil` 表示该行不可删
/// （引导 Moment），不挂任何删除相关修饰符。
struct TimelineRowView: View {
    let entry: TimelineEntry
    let onTap: () -> Void
    var onDelete: (() -> Void)?

    @Environment(ThemeManager.self) private var theme

    /// 竖线相对本行内容左边缘的固定水平偏移：日期列宽度(64) + 列间距(12) +
    /// 心情节点列宽度一半(12)，与心情节点圆点的水平中心对齐（见 `nodeColumn`）。
    ///
    /// **用一条贯穿整行（卡片高度 + 行间延伸段）的背景竖线**取代此前「行内竖线 + 独立延伸
    /// 竖线」两段拼接画法——两段各自的居中计算方式不同（前者在 24pt 列内居中，后者未居中
    /// 直接贴在列起点），导致每行边界处竖线水平错位、视觉断裂，与公理层「时间轴是连续对象，
    /// Moment/日期/心情节点是挂载其上」的对象设计相悖（阶段 4 修正，见 code review）。
    private static let railLineLeadingOffset: CGFloat = 64 + 12 + 12

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                dateColumn
                nodeColumn
                BubbleCardView(
                    title: entry.title,
                    bodyText: entry.bodyText,
                    tagNames: entry.tagNames,
                    placeholderImageHexColors: entry.placeholderImageHexColors,
                    imageIDs: entry.imageIDs
                )
                .onTapGesture {
                    guard !entry.isGuided else { return }
                    onTap()
                }
            }

            // 行间延伸段：只占位，不再单独画线——竖线统一由下方 `background` 贯穿整行绘制。
            Color.clear.frame(height: 20)
        }
        .background(alignment: .topLeading) {
            Rectangle()
                .fill(theme.timelineRail)
                .frame(width: 1)
                .padding(.leading, Self.railLineLeadingOffset)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(entry.accessibilityLabel))
        .accessibilityAddTraits(entry.isGuided ? [] : .isButton)
        .modifier(SwipeToDeleteModifier(onDelete: onDelete))
    }

    // MARK: - 日期列（宽度约 64pt，见 05 §5.5）

    private var dateColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(dayText).font(AppTypography.timelineDayNumber)
                Text(monthText).font(AppTypography.timelineMonth)
            }
            .foregroundStyle(theme.primaryText)

            Text(timeText)
                .font(AppTypography.timelineTime)
                .foregroundStyle(theme.bubbleBodyText)
        }
        .frame(width: 64, alignment: .leading)
    }

    // MARK: - 时间线列（宽度约 24pt，心情节点；竖线由 `body` 的贯穿式 `background` 统一绘制，见 05 §5.5）

    private var nodeColumn: some View {
        MoodNodeView(mood: entry.mood)
            .padding(.top, 6)
            .frame(width: 24, alignment: .top)
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

    /// 24 小时制时间格式化器缓存：DateFormatter 构造昂贵，避免逐行、逐次 body 求值重建。
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

/// 左滑删除动作 + 无障碍替代路径（见 04-screen-specs.md §4.1：首页删除无需二次确认，
/// 有垃圾箱兜底，见公理3）。`onDelete == nil` 时不挂任何修饰符（引导 Moment 不可删）。
private struct SwipeToDeleteModifier: ViewModifier {
    let onDelete: (() -> Void)?

    func body(content: Content) -> some View {
        if let onDelete {
            content
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .accessibilityIdentifier("timelineSwipeDeleteButton")
                }
                .accessibilityAction(named: Text("删除")) { onDelete() }
        } else {
            content
        }
    }
}
