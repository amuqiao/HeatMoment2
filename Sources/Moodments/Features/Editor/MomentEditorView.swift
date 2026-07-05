import SwiftUI

/// 占位 stub：阶段 2 只验证「点击悬浮新建按钮 → 以任务卡片栈（`.sheet`）打开编辑器」的呈现机制
/// 跑通（见 08-architecture.md §2.2）。情绪/标签/日期/时间/照片/保存等真实内容在阶段 3 实现。
struct MomentEditorView: View {
    let mode: EditorMode

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("编辑器 · 阶段3")
                    .font(.title2.bold())
                Text(modeDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private var modeDescription: String {
        switch mode {
        case .create: "新建态"
        case let .edit(id): "编辑态 · \(id)"
        }
    }
}

#Preview {
    MomentEditorView(mode: .create)
}
