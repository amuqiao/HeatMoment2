import SwiftUI

/// 顶部栏左侧：方形圆角徽标，内嵌当日日期数字，点击展开 `YearHeatmapView`（见 docs/current/implementation-truth.md §5.6）。
/// 透明内芯 + 顶部实心帽 + 粗外框，中性色随亮/暗模式反转，不跟随主色着色。
struct CalendarIconButtonView: View {
    var style: HomeChromeIconStyle = .standard
    let action: () -> Void

    @Environment(ThemeManager.self) private var theme

    private var dayNumber: String {
        String(Calendar.current.component(.day, from: .now))
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(theme.neutralIconStroke)
                    .frame(height: calendarHeaderHeight)
                    .frame(maxHeight: .infinity, alignment: .top)

                RoundedRectangle(cornerRadius: style.calendarCornerRadius, style: .continuous)
                    .stroke(theme.neutralIconStroke, lineWidth: style.strokeWidth)

                Text(dayNumber)
                    .font(
                        .system(
                            size: calendarDayFontSize,
                            weight: .bold,
                            design: .rounded
                        )
                        .monospacedDigit()
                    )
                    .foregroundStyle(theme.neutralIconStroke)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(
                        width: style.calendarSize.width,
                        height: style.calendarSize.height - calendarHeaderHeight,
                        alignment: .center
                    )
                    .offset(y: calendarHeaderHeight)
            }
            .clipShape(
                RoundedRectangle(cornerRadius: style.calendarCornerRadius, style: .continuous)
            )
            .frame(width: style.calendarSize.width, height: style.calendarSize.height)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("年度心情热力图"))
    }

    private var calendarDayFontSize: CGFloat {
        min(style.calendarSize.width, style.calendarSize.height) * style.calendarDayFontRatio
    }

    private var calendarHeaderHeight: CGFloat {
        style.calendarSize.height * style.calendarHeaderHeightRatio
    }
}

/// 顶部栏右侧：六边形描边图标，点击打开 `SettingsSheetView`（见 docs/current/implementation-truth.md §5.6）。
/// 粗描边六边形 + 中心实心点，中性色随亮/暗模式反转，不跟随主色着色。
struct HexagonIconButtonView: View {
    var style: HomeChromeIconStyle = .standard
    let action: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button(action: action) {
            ZStack {
                HexagonShape()
                    .stroke(
                        theme.neutralIconStroke,
                        style: StrokeStyle(
                            lineWidth: style.strokeWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .padding(style.strokeWidth / 2)

                Circle()
                    .fill(theme.neutralIconStroke)
                    .frame(
                        width: style.settingsDotDiameter,
                        height: style.settingsDotDiameter
                    )
            }
            .frame(width: style.settingsSize.width, height: style.settingsSize.height)
        }
        .buttonStyle(.plain)
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
