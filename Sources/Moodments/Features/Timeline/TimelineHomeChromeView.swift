import SwiftUI

/// 首页顶部 chrome：日历入口、收起态标题筛选入口、设置入口。
///
/// 该组件只表达首页固定入口，不持有筛选、热力图或设置的呈现状态；具体呈现由
/// `TimelineHomeView` 组合的 presenter 决定。这样后续调整入口样式、热力图展开方式或筛选
/// sheet detent 时，不需要改动时间轴列表和数据查询。
struct TimelineHomeChromeView: View {
    let isTitleCollapsed: Bool
    let isContextPanelPresented: Bool
    let onCalendarTapped: () -> Void
    let onFilterTapped: () -> Void
    let onSettingsTapped: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack {
            CalendarIconButtonView(action: onCalendarTapped)
            Spacer()
            if isTitleCollapsed {
                collapsedTitleButton
                    .transition(.opacity)
            }
            Spacer()
            HexagonIconButtonView(action: onSettingsTapped)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background { chromeBackground }
        .animation(.easeInOut(duration: 0.2), value: isTitleCollapsed)
    }

    @ViewBuilder
    private var chromeBackground: some View {
        if isContextPanelPresented {
            HomeSceneBackgroundView().ignoresSafeArea(edges: .top)
        } else if isTitleCollapsed {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(theme.canvasBackground.opacity(0.36))
                .ignoresSafeArea(edges: .top)
        } else {
            Color.clear.ignoresSafeArea(edges: .top)
        }
    }

    private var collapsedTitleButton: some View {
        Button(action: onFilterTapped) {
            HStack(spacing: 4) {
                Text("时刻")
                Image(systemName: "chevron.down")
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(theme.primaryText)
        }
        .accessibilityIdentifier("timelineCollapsedTitleButton")
        .accessibilityLabel(Text("时刻，筛选入口"))
        .accessibilityHint(Text("双击打开标签与心情筛选"))
    }
}

#Preview {
    TimelineHomeChromeView(
        isTitleCollapsed: true,
        isContextPanelPresented: false,
        onCalendarTapped: {},
        onFilterTapped: {},
        onSettingsTapped: {}
    )
    .environment(ThemeManager())
}
