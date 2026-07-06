import SwiftUI

/// 情绪选择就近浮窗（见 `docs/design/04-screen-specs.md` §4.5、05-design-system.md §5.6/§5.7）：
/// `Mood.allCases` 8 行 emoji+名称，当前项右侧 `✓` + 8% 主色高亮；点选即选中并回填、关闭浮窗
/// （由调用方在 `onSelect` 内把 `isPresented` 置为 `false`，本视图不持有呈现状态）。
///
/// **呈现机制**：由调用方以 `.popover(isPresented:) { MoodPickerView(...).presentationCompactAdaptation(.popover) }`
/// 挂载，本视图不感知自己"如何被展示"（依 ADR-006：就近浮窗跨设备保持锚定浮窗形态）。
struct MoodPickerView: View {
    let selectedMood: Mood
    let onSelect: (Mood) -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Mood.allCases) { mood in
                Button {
                    onSelect(mood)
                } label: {
                    HStack {
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
                    // 显式 `maxWidth: .infinity` 撑满行宽：popover 内容默认按子视图理想尺寸
                    // 收缩，若不撑满，`Spacer()` 会退化为 0 宽、导致该行的可命中区域退化为
                    // 一个零面积矩形（曾在 UI 测试中复现为 XCUITest 无法计算有效命中点）；
                    // `contentShape` 确保整行（含空白区）而非仅文字/背景绘制区域可点击。
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .background(mood == selectedMood ? theme.accent.opacity(0.08) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("moodOption-\(mood.rawValue)")
                .accessibilityLabel(Text("\(mood.emoji) \(mood.displayName)"))
                .accessibilityAddTraits(mood == selectedMood ? [.isSelected] : [])
            }
        }
        // 用固定 `width` 而非 `minWidth`：内部各行用 `maxWidth: .infinity` 撑满行宽需要一个
        // 明确的父级宽度可解析，`minWidth` 在 popover 的「按内容尺寸」布局下不提供该约束。
        .frame(width: 240)
        // `.popover` 对内容的默认尺寸测算在这种「宽度已固定、高度按内容」的场景下会算错
        // （曾实测复现为 8 行内容被错误地压成约 132pt 高、多数行渲染在可见浮窗范围之外，
        // 导致 XCUITest 无法计算有效命中点）；显式 `fixedSize(vertical: true)` 强制按内容
        // 理想高度布局，规避该系统测算问题。
        .fixedSize(horizontal: false, vertical: true)
        .background(theme.sheetBackground)
    }
}

#Preview {
    MoodPickerView(selectedMood: .happy) { _ in }
        .environment(ThemeManager())
}
