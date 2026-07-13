import SwiftUI

/// 情绪选择就近浮窗（见 `docs/current/implementation-truth.md` §4.5/§5.6/§5.7）：
/// `Mood.allCases` 8 行 emoji+名称，当前项右侧 `✓` + 8% 主色高亮；点选即选中并回填、关闭浮窗
/// （由调用方在 `onSelect` 内把 `isPresented` 置为 `false`，本视图不持有呈现状态）。
///
/// **呈现机制**：由编辑页内部 overlay 锚定在情绪按钮下方；这是应用内菜单，不使用系统
/// `.popover`，因此没有尖角，并能在键盘存在时按可用高度收缩为内部滚动列表。
struct MoodPickerView: View {
    let selectedMood: Mood
    let maxHeight: CGFloat
    let onSelect: (Mood) -> Void

    @Environment(ThemeManager.self) private var theme

    init(
        selectedMood: Mood,
        maxHeight: CGFloat = .infinity,
        onSelect: @escaping (Mood) -> Void
    ) {
        self.selectedMood = selectedMood
        self.maxHeight = maxHeight
        self.onSelect = onSelect
    }

    var body: some View {
        let height = EditorFloatingPickerMetrics.resolvedHeight(
            rowCount: Mood.allCases.count,
            maxHeight: maxHeight
        )

        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(Mood.allCases.enumerated()), id: \.element.id) { index, mood in
                    Button {
                        onSelect(mood)
                    } label: {
                        HStack(spacing: 10) {
                            Text(mood.emoji)
                            Text(mood.displayName)
                                .foregroundStyle(theme.primaryText)
                            Spacer()
                            if mood == selectedMood {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(theme.primaryText)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: EditorFloatingPickerMetrics.rowHeight,
                            alignment: .leading
                        )
                        .background(mood == selectedMood ? theme.selectionFill : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("moodOption-\(mood.rawValue)")
                    .accessibilityLabel(Text("\(mood.emoji) \(mood.displayName)"))
                    .accessibilityAddTraits(mood == selectedMood ? [.isSelected] : [])

                    if index < Mood.allCases.count - 1 {
                        Rectangle()
                            .fill(theme.separator)
                            .frame(height: EditorFloatingPickerMetrics.separatorHeight)
                    }
                }
            }
        }
        .scrollIndicators(scrollIndicatorVisibility(contentHeight: contentHeight, height: height))
        .frame(width: EditorFloatingPickerMetrics.width, height: height)
        .background(theme.sheetPanelBackground)
        .clipShape(
            RoundedRectangle(
                cornerRadius: EditorFloatingPickerMetrics.cornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: EditorFloatingPickerMetrics.cornerRadius,
                style: .continuous
            )
            .stroke(theme.separator, lineWidth: EditorFloatingPickerMetrics.separatorHeight)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
        .accessibilityIdentifier("editorMoodPickerMenu")
    }

    private var contentHeight: CGFloat {
        EditorFloatingPickerMetrics.listHeight(rowCount: Mood.allCases.count)
    }

    private func scrollIndicatorVisibility(
        contentHeight: CGFloat,
        height: CGFloat
    ) -> ScrollIndicatorVisibility {
        height < contentHeight ? .visible : .hidden
    }
}

#Preview {
    MoodPickerView(selectedMood: .happy) { _ in }
        .environment(ThemeManager())
}
