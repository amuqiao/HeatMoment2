import SwiftUI

/// 占位 stub：阶段 2 只验证「点击顶部左侧日历方块 → 以覆盖层（`ZStack` overlay，非模态）展开
/// 年度热力图」的呈现机制跑通（见 08-architecture.md §2.2）。年份切换、日期格着色、定位滚动在
/// 阶段 5 实现。
struct YearHeatmapView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button {
                        router.isHeatmapPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel(Text("关闭"))
                }
                Spacer()
                Text("热力图 · 阶段5")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(20)
        }
    }
}

#Preview {
    YearHeatmapView()
        .environment(AppRouter())
}
