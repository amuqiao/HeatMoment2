import SwiftUI

/// 占位 stub：阶段 2 只验证「点击顶部右侧六边形 → 以任务卡片栈（`.sheet`）打开设置」的呈现机制
/// 跑通（见 08-architecture.md §2.2）。分组卡片、Pro 横幅、各子页在阶段 6 实现。
struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("设置 · 阶段6")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("设置")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                }
        }
    }
}

#Preview {
    SettingsSheetView()
}
