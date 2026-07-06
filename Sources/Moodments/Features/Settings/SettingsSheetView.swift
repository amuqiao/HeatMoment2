import SwiftUI

/// 设置（见 `docs/design/04-screen-specs.md` §4.11）：完整分组卡片、Pro 横幅等留阶段 6 实现；
/// 本阶段仅最小托管——加入「垃圾箱」入口（`NavigationLink` push，见 08-architecture.md §2.2
/// 设置栈内子页映射），使删除生命周期的规范入口可达、可测。
struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("垃圾箱") {
                    TrashView()
                }
                .accessibilityIdentifier("settingsTrashRow")
            }
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
