import Foundation
import SwiftUI

/// 占位 stub：阶段 2 只验证「点击时间轴卡片 → 弹出阅读卡片（任务卡片栈，非 push）」的呈现机制
/// 跑通（见 04-screen-specs.md §4.9、14-design-decisions.md ADR-007）。完整预览内容在阶段 4 实现。
struct MomentPreviewView: View {
    let momentID: UUID

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("预览 · 阶段4")
                    .font(.title2.bold())
                Text(momentID.uuidString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
