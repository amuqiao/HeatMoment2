import SwiftUI

/// 时间轴心情节点（见 05-design-system.md §5.5）：直径约 12–14pt 的纯色圆点，
/// 填充色为**该条时刻情绪对应的心情色**（见 `MoodColorPalette`），不是固定色、不是统一色点
/// （依 `product-mental-model.md` 公理1「心情色一致性」）。
///
/// 情绪辨识不单靠节点颜色——气泡内容/情绪选择器/统计页均有 emoji + 名称冗余（见 05 §5.10.3），
/// 故节点本身不重复承担无障碍朗读职责，由所在行的 `accessibilityElement(children: .combine)`
/// 统一在卡片上给出完整 label。
struct MoodNodeView: View {
    let mood: Mood
    var diameter: CGFloat = 13

    var body: some View {
        Circle()
            .fill(MoodColorPalette.color(for: mood))
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 12) {
        ForEach(Mood.allCases) { mood in
            MoodNodeView(mood: mood)
        }
    }
    .padding()
    .background(Color(hex: 0x121221))
}
