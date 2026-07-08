import SwiftUI

/// 悬浮新建按钮（FAB，见 05-design-system.md §5.6）：直径约 64pt 圆形，居中吸底，
/// 填充色 = 当前主色，内容为白色描边加号图标，带轻微阴影制造「悬浮」层次。
struct FABButtonView: View {
    let action: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(theme.accent)
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(theme.onAccentText)
                )
                .shadow(color: theme.floatingActionShadow, radius: 12, x: 0, y: 4)
        }
        .accessibilityLabel(Text("新建时刻"))
    }
}

#Preview {
    FABButtonView {}
        .environment(ThemeManager())
        .padding()
        .background(Color(hex: 0x121221))
}
