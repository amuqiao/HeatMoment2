import SwiftUI

/// 占位 stub：阶段 2 只验证「点击收起态标题『时刻 ⌄』→ 以就近浮窗（`.popover` +
/// `presentationCompactAdaptation(.popover)`）打开筛选面板」的呈现机制跑通，且**不进
/// `AppRouter`**（由 `TimelineHomeView` 的局部 `@State` 就近驱动，见 08-architecture.md §2.2/§3）。
/// 标签/心情筛选的真实交互与 `TimelineModel.activeFilter` 接线在阶段 5 实现。
struct FilterPanelView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("筛选 · 阶段5")
                .font(.headline)
            Text("标签 / 心情筛选面板将在阶段 5 实现")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 240)
    }
}

#Preview {
    FilterPanelView()
}
