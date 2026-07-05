import SwiftUI

/// 占位 stub：仅为满足 `AppRouter.RootSheet` 的穷尽匹配（阶段 2 导航骨架未接 Paywall 触发路径）。
/// 完整订阅/买断内容在阶段 7 实现（见 08-architecture.md §6、11-monetization.md）。
struct ProPaywallView: View {
    let trigger: PaywallTrigger

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Pro 订阅 · 阶段7")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                }
        }
    }
}

#Preview {
    ProPaywallView(trigger: .banner)
}
