import SwiftUI

/// 阶段 0 占位根视图：仅验证脚手架可 build & run。
/// 阶段 2 将替换为 TimelineHomeView（时间轴首页）。
struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("时刻")
                .font(.largeTitle.bold())
            Text("脚手架就绪 · 阶段 0")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RootView()
}
