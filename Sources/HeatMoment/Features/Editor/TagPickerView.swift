import SwiftUI

/// 标签选择就近浮窗（见 `docs/current/implementation-truth.md` §4.6）：只展示已有标签；
/// 点已有标签**多选**（点选切换、不关闭浮窗，由调用方保持 `isPresented`）。
/// 标签新增、重命名、删除归属设置页 `TagManageView`，本浮窗只消费既有标签。
struct TagPickerView: View {
    let selectedTagIDs: [UUID]
    let maxHeight: CGFloat
    let onToggle: (TagSnapshot) -> Void

    @Environment(ThemeManager.self) private var theme
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(CanonicalLibraryService.self) private var canonicalService
    @State private var tags: [TagSnapshot] = []

    init(
        selectedTagIDs: [UUID],
        maxHeight: CGFloat = .infinity,
        onToggle: @escaping (TagSnapshot) -> Void
    ) {
        self.selectedTagIDs = selectedTagIDs
        self.maxHeight = maxHeight
        self.onToggle = onToggle
    }

    var body: some View {
        let rowCount = max(tags.count, 1)
        let height = EditorFloatingPickerMetrics.resolvedHeight(
            rowCount: rowCount,
            maxHeight: maxHeight
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(tags.enumerated()), id: \.element.id) { index, tag in
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
                        .frame(
                            maxWidth: .infinity,
                            minHeight: EditorFloatingPickerMetrics.rowHeight,
                            alignment: .leading
                        )
                        .background(isSelected ? theme.selectionFill : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tagOption-\(tag.name)")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityValue(Text(isSelected ? "已选中" : ""))

                    if index < tags.count - 1 {
                        Rectangle()
                            .fill(theme.separator)
                            .frame(height: EditorFloatingPickerMetrics.separatorHeight)
                    }
                }

                if tags.isEmpty {
                    Text("还没有标签")
                        .font(AppTypography.caption)
                        .foregroundStyle(theme.secondaryText)
                        .padding(.horizontal, 16)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: EditorFloatingPickerMetrics.rowHeight,
                            alignment: .leading
                        )
                        .accessibilityIdentifier("tagPickerEmptyState")
                }
            }
        }
        .scrollIndicators(scrollIndicatorVisibility(rowCount: rowCount, height: height))
        .frame(width: EditorFloatingPickerMetrics.width, height: height)
        .background(theme.sheetPanelBackground)
        .clipShape(
            RoundedRectangle(
                cornerRadius: EditorFloatingPickerMetrics.cornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: EditorFloatingPickerMetrics.cornerRadius,
                style: .continuous
            )
            .stroke(theme.separator, lineWidth: EditorFloatingPickerMetrics.separatorHeight)
        }
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
        .accessibilityIdentifier("editorTagPickerMenu")
        // 本视图是编辑页自绘浮层内容，同 `TagCreateSheetView` 的遮挡问题：父级
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

    private func scrollIndicatorVisibility(
        rowCount: Int,
        height: CGFloat
    ) -> ScrollIndicatorVisibility {
        let contentHeight = EditorFloatingPickerMetrics.listHeight(rowCount: rowCount)
        return height < contentHeight ? .visible : .hidden
    }
}
