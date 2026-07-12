import SwiftUI

/// 悬浮新建按钮（FAB，见 docs/current/implementation-truth.md §5.6）：直径约 64pt 圆形，居中吸底，
/// 填充色 = 当前主色，内容为白色描边加号图标，带轻微阴影制造「悬浮」层次。
struct FABButtonView: View {
    let diameter: CGFloat
    let style: FABStyle
    let action: () -> Void

    @Environment(ThemeManager.self) private var theme

    init(
        diameter: CGFloat,
        style: FABStyle = .standard,
        action: @escaping () -> Void
    ) {
        self.diameter = diameter
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(theme.accent)
                .frame(
                    width: diameter,
                    height: diameter
                )
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: style.iconSize, weight: style.iconWeight))
                        .foregroundStyle(theme.onAccentText)
                )
                .shadow(
                    color: theme.floatingActionShadow,
                    radius: style.shadowRadius,
                    x: 0,
                    y: style.shadowYOffset
                )
        }
        .accessibilityLabel(Text("新建时刻"))
    }
}

#Preview {
    FABButtonView(diameter: 64) {}
        .environment(ThemeManager())
        .padding()
        .background(Color(hex: 0x121221))
}
