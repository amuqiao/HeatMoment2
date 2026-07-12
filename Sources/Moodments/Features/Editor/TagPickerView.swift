import SwiftUI

/// 标签选择就近浮窗（见 `docs/current/implementation-truth.md` §4.6）：只展示已有标签；
/// 点已有标签**多选**（点选切换、不关闭浮窗，由调用方保持 `isPresented`）。
/// 标签新增、重命名、删除归属设置页 `TagManageView`，本浮窗只消费既有标签。
struct TagPickerView: View {
    let selectedTagIDs: [UUID]
    let onToggle: (TagSnapshot) -> Void

    @Environment(ThemeManager.self) private var theme
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(CanonicalLibraryService.self) private var canonicalService
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
                    .background(isSelected ? theme.selectionFill : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tagOption-\(tag.name)")
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(Text(isSelected ? "已选中" : ""))
            }

            if tags.isEmpty {
                Text("还没有标签")
                    .font(AppTypography.caption)
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("tagPickerEmptyState")
            }
        }
        // 用固定 `width` 而非 `minWidth`：见 `MoodPickerView` 同类注释。
        .frame(width: 240)
        // 见 `MoodPickerView` 同类注释：强制按内容理想高度布局，规避 `.popover` 默认尺寸
        // 测算把动态行数内容压扁、导致行渲染在可见浮窗范围之外的问题。
        .fixedSize(horizontal: false, vertical: true)
        .background(theme.sheetBackground)
        // 本视图是就近浮窗（`.popover`）内容，同 `TagCreateSheetView` 的遮挡问题：父级
        // （`MomentEditorView`）挂的 `.userFacingErrorAlert` 未必能弹到浮窗之上，故本视图自行
        // 挂一份，绑定同一份共享 `ErrorPresenter`。
        .userFacingErrorAlert(errorPresenter)
        .task {
            do {
                tags = try await canonicalService.fetchFilterTags()
            } catch {
                errorPresenter.report(message: "标签列表加载失败，请稍后重试。", underlying: error)
            }
        }
    }
}
