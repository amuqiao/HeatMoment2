import SwiftUI

/// 首页上下文面板槽位。
///
/// 目前用于热力图从顶部栏日历入口附近展开；转场由本 presenter 统一持有，不让热力图内容、
/// 时间轴列表或顶部 chrome 知道具体动效。
struct HomeContextPanel<Content: View>: View {
    let isPresented: Bool
    let anchorXRatio: CGFloat
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isPresented {
            content()
                .transition(
                    .homeContextPanelAnchor(
                        anchorXRatio: anchorXRatio,
                        reduceMotion: reduceMotion
                    )
                )
                .zIndex(1)
        }
    }
}

private struct HomeContextPanelAnchorModifier: ViewModifier {
    let opacity: Double
    let scale: CGFloat
    let anchorXRatio: CGFloat
    let yOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale, anchor: UnitPoint(x: anchorXRatio, y: 0))
            .offset(y: yOffset)
    }
}

private extension AnyTransition {
    static func homeContextPanelAnchor(
        anchorXRatio: CGFloat,
        reduceMotion: Bool
    ) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }

        return .modifier(
            active: HomeContextPanelAnchorModifier(
                opacity: 0,
                scale: 0.96,
                anchorXRatio: anchorXRatio,
                yOffset: -8
            ),
            identity: HomeContextPanelAnchorModifier(
                opacity: 1,
                scale: 1,
                anchorXRatio: anchorXRatio,
                yOffset: 0
            )
        )
    }
}

/// 首页筛选 half-sheet presenter。
///
/// 筛选属于首页就地精炼，不进入 `AppRouter` 的任务卡片栈。把 sheet 修饰符集中到这里，可以让
/// 后续 detent、drag indicator、第二层标签创建策略的调整不影响 `TimelineHomeView` 主结构。
private struct TimelineFilterSheetPresenter: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var activeFilter: FilterCondition?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                FilterPanelView(activeFilter: $activeFilter)
                    .presentationDetents([.medium, .large])
            }
    }
}

extension View {
    func timelineFilterSheet(
        isPresented: Binding<Bool>,
        activeFilter: Binding<FilterCondition?>
    ) -> some View {
        modifier(TimelineFilterSheetPresenter(isPresented: isPresented, activeFilter: activeFilter))
    }
}
