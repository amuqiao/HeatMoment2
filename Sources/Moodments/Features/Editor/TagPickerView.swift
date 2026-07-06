import SwiftData
import SwiftUI

/// 标签选择就近浮窗（见 `docs/design/04-screen-specs.md` §4.6）：已有标签列表 + 末尾
/// 「+添加」入口；点已有标签**多选**（点选切换、不关闭浮窗，由调用方保持 `isPresented`）；
/// 点「+添加」交由调用方处理（额度校验 + 打开 `TagCreateSheetView`，属任务卡片栈的第二层，
/// 见 08-architecture.md §2.2）。
struct TagPickerView: View {
    let modelContainer: ModelContainer
    let selectedTagIDs: [UUID]
    let onToggle: (TagSnapshot) -> Void
    let onRequestCreate: () -> Void

    @Environment(ThemeManager.self) private var theme
    @State private var tags: [TagSnapshot] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(tags) { tag in
                let isSelected = selectedTagIDs.contains(tag.id)
                Button {
                    onToggle(tag)
                } label: {
                    HStack {
                        Text("#\(tag.name)")
                            .foregroundStyle(theme.primaryText)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(theme.primaryText)
                        }
                    }
                    .padding(.horizontal, 16)
                    // 见 `MoodPickerView` 同类注释：撑满行宽 + 显式命中形状，避免 `Spacer()`
                    // 在未约束宽度的 popover 内容中退化为零宽、导致行不可命中。
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(isSelected ? theme.accent.opacity(0.08) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tagOption-\(tag.name)")
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(Text(isSelected ? "已选中" : ""))
            }

            if !tags.isEmpty {
                Divider()
            }

            Button {
                onRequestCreate()
            } label: {
                Label("添加", systemImage: "plus")
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tagCreateEntryButton")
        }
        // 用固定 `width` 而非 `minWidth`：见 `MoodPickerView` 同类注释。
        .frame(width: 240)
        // 见 `MoodPickerView` 同类注释：强制按内容理想高度布局，规避 `.popover` 默认尺寸
        // 测算把动态行数内容压扁、导致行渲染在可见浮窗范围之外的问题。
        .fixedSize(horizontal: false, vertical: true)
        .background(theme.sheetBackground)
        .task {
            do {
                tags = try await TagRepository(modelContainer: modelContainer).fetchAll()
            } catch {
                assertionFailure("标签列表加载失败：\(error)")
            }
        }
    }
}
