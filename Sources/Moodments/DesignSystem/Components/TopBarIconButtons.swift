import SwiftUI

/// 顶部栏左侧：方形圆角徽标，内嵌当日日期数字，点击展开 `YearHeatmapView`（见 05 §5.6）。
/// 线性描边、中性色，不跟随主色着色。
struct CalendarIconButtonView: View {
    var style: HomeChromeIconStyle = .standard
    let action: () -> Void

    @Environment(ThemeManager.self) private var theme

    private var dayNumber: String {
        String(Calendar.current.component(.day, from: .now))
    }

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: style.calendarCornerRadius, style: .continuous)
                .stroke(theme.neutralIconStroke, lineWidth: style.strokeWidth)
                .frame(width: style.calendarSize.width, height: style.calendarSize.height)
                .overlay(
                    Text(dayNumber)
                        .font(.caption.bold())
                        .foregroundStyle(theme.neutralIconStroke)
                )
        }
        .accessibilityLabel(Text("年度心情热力图"))
    }
}

/// 顶部栏右侧：六边形描边图标，点击打开 `SettingsSheetView`（见 05 §5.6）。
/// 线性描边、中性色，不跟随主色着色。
struct HexagonIconButtonView: View {
    var style: HomeChromeIconStyle = .standard
    let action: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button(action: action) {
            HexagonShape()
                .stroke(theme.neutralIconStroke, lineWidth: style.strokeWidth)
                .frame(width: style.settingsSize.width, height: style.settingsSize.height)
        }
        .accessibilityLabel(Text("设置"))
    }
}

/// 正六边形，供 `HexagonIconButtonView` 描边使用。
private struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = (0..<6).map { index -> CGPoint in
            let angle = Angle(degrees: Double(index) * 60 - 90)
            return CGPoint(
                x: rect.midX + rect.width / 2 * cos(angle.radians),
                y: rect.midY + rect.height / 2 * sin(angle.radians)
            )
        }
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

#Preview {
    HStack(spacing: 20) {
        CalendarIconButtonView {}
        HexagonIconButtonView {}
    }
    .environment(ThemeManager())
    .padding()
    .background(Color(hex: 0x121221))
}
