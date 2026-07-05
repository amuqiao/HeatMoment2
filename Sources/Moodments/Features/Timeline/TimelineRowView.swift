import SwiftUI

/// 时间轴一行：日期列 + 心情节点（按该条情绪的心情色着色）+ 气泡卡片（见 05-design-system.md §5.5）。
/// 预置引导 Moment 不可点（`isGuided`），真实 Moment 点击弹出预览阅读卡片（见 04-screen-specs.md §4.1）。
struct TimelineRowView: View {
    let entry: TimelineEntry
    let onTap: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                dateColumn
                railColumn
                BubbleCardView(
                    title: entry.title,
                    bodyText: entry.bodyText,
                    tagNames: entry.tagNames,
                    placeholderImageHexColors: entry.placeholderImageHexColors
                )
                .onTapGesture {
                    guard !entry.isGuided else { return }
                    onTap()
                }
            }

            // 竖线延伸段：填补卡片间的垂直间距，让时间线视觉保持连续（见 05 §5.5）。
            HStack(spacing: 12) {
                Color.clear.frame(width: 64)
                Rectangle()
                    .fill(theme.timelineRail)
                    .frame(width: 1)
                Spacer(minLength: 0)
            }
            .frame(height: 20)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(entry.accessibilityLabel))
        .accessibilityAddTraits(entry.isGuided ? [] : .isButton)
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

    // MARK: - 时间线列（宽度约 24pt，竖线 + 心情节点，见 05 §5.5）

    private var railColumn: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(theme.timelineRail)
                .frame(width: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            MoodNodeView(mood: entry.mood)
                .padding(.top, 6)
        }
        .frame(width: 24)
    }

    private var dayText: String {
        String(Calendar.current.component(.day, from: entry.occurredAt))
    }

    private var monthText: String {
        "\(Calendar.current.component(.month, from: entry.occurredAt))月"
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: entry.occurredAt)
    }
}
