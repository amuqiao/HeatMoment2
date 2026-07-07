import SwiftUI

/// 首页上下文面板槽位。
///
/// 目前用于热力图在导航栏下方原位展开；未来如果产品裁决为右侧抽屉或其它转场，应优先改这个
/// presenter，而不是让热力图内容、时间轴列表或顶部 chrome 知道具体动效。
struct HomeContextPanel<Content: View>: View {
    let isPresented: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        if isPresented {
            content()
                .transition(.move(edge: .top).combined(with: .opacity))
        }
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
