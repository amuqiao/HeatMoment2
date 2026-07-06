import SwiftUI

/// 心情统计条形（见 `docs/design/04-screen-specs.md` §4.12、`docs/design/05-design-system.md` §5.6/§5.4）：
/// 「emoji+名称」（左）+「N 次」（右）+ 进度条；轨道底色为该情绪心情色 15% 透明度叠加，
/// 填充为该情绪满值强度色，宽度按占比渲染。文字/emoji/数字三重编码，不依赖颜色单独传达
/// （见 05 §5.10.3 色盲友好设计），情绪色只用于填充/图形，不渲染成文字（见 05 §5.10.1 结论）。
struct MoodStatBarView: View {
    let mood: Mood
    let count: Int
    let totalCount: Int

    @Environment(ThemeManager.self) private var theme

    private var fraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(count) / Double(totalCount)
    }

    private var percentText: String {
        guard totalCount > 0 else { return "0%" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(mood.emoji) \(mood.displayName)")
                    .font(AppTypography.body)
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text("\(count)次")
                    .font(AppTypography.caption)
                    .foregroundStyle(theme.bubbleBodyText)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.moodColor(mood).opacity(0.15))
                    Capsule()
                        .fill(theme.moodColor(mood))
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(mood.displayName)，\(count)次，占比\(percentText)"))
        .accessibilityIdentifier("moodStatBar-\(mood.rawValue)")
    }
}

#Preview {
    VStack(spacing: 12) {
        MoodStatBarView(mood: .happy, count: 3, totalCount: 5)
        MoodStatBarView(mood: .sad, count: 2, totalCount: 5)
    }
    .padding()
    .environment(ThemeManager())
}
