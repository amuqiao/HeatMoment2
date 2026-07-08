import SwiftData
import SwiftUI

/// 标签/心情筛选面板（见 `docs/design/04-screen-specs.md` §4.2）：从首页收起态标题
/// 「时刻 ⌄」升起的**半屏 bottom sheet**（交互模型 v2 修订，见 ADR-006 `[AMENDED v2]`——
/// 筛选从就近浮窗 popover 解耦为 `.presentationDetents([.medium, .large])` 的 sheet，因其
/// 要同时承载心情单选 + 标签多选，popover 里会拥挤）。呈现容器改变，但筛选其余性质不变：
/// **不进 `AppRouter`**、由触发处局部 `@State` 驱动、就地即时生效。
///
/// **筛选组合逻辑**（已裁决，见 04 §4.2、`docs/design/13-open-questions.md` #19）：标签
/// **多选**、彼此 **AND**（交集）；心情**单选**；标签维度与心情维度之间也是 AND。
/// 每次点选**即时更新** `activeFilter`（就地生效，无「确认」按钮）；「完成」仅收起 sheet、
/// 不做提交。筛选面板只选择已有标签；新增、重命名、删除标签归属设置页 `TagManageView`。
///
/// **布局取舍（网格 chips）**：标签区改为 `LazyVGrid` 自适应网格，避免 bottom sheet 被
/// 单行 `List` 撑得过长；心情同样用网格，并显式提供「全部心情」入口，半屏下仍能直接完成
/// 常用筛选。
struct FilterPanelView: View {
    @Binding var activeFilter: FilterCondition?

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.createdAt) private var tags: [Tag]

    private var selectedTagIDs: Set<UUID> { activeFilter?.tagIDs ?? [] }
    private var selectedMood: Mood? { activeFilter?.mood }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    filterSectionTitle("标签")

                    if tags.isEmpty {
                        Text("还没有标签")
                            .font(AppTypography.caption)
                            .foregroundStyle(theme.secondaryText)
                            .accessibilityIdentifier("filterNoTagsHint")
                    } else {
                        LazyVGrid(columns: tagGridColumns, alignment: .leading, spacing: 10) {
                            ForEach(tags) { tag in
                                tagChip(tag)
                            }
                        }
                    }

                    filterSectionTitle("心情")

                    LazyVGrid(columns: moodGridColumns, alignment: .leading, spacing: 10) {
                        allMoodChip
                        ForEach(Mood.allCases) { mood in
                            moodChip(mood)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollContentBackground(.hidden)
            .background(theme.sheetBackground.ignoresSafeArea())
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("清除全部") {
                        activeFilter = nil
                    }
                    .disabled(activeFilter?.isEmpty ?? true)
                    .accessibilityIdentifier("filterClearButton")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("filterDoneButton")
                }
            }
        }
        .themedTaskContainer(theme)
        .presentationBackground(theme.sheetBackground)
    }

    private var tagGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 116), spacing: 10, alignment: .leading)]
    }

    private var moodGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 112), spacing: 10, alignment: .leading)]
    }

    private func filterSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.cardTitle)
            .foregroundStyle(theme.primaryText)
    }

    private func tagChip(_ tag: Tag) -> some View {
        let isSelected = selectedTagIDs.contains(tag.id)
        return Button {
            toggleTag(tag.id)
        } label: {
            HStack(spacing: 6) {
                Text("#\(tag.name)")
                    .font(AppTypography.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                }
            }
            .foregroundStyle(isSelected ? theme.onAccentText : theme.primaryText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 10)
            .background {
                Capsule()
                    .fill(isSelected ? theme.accent : theme.chipFill)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filterTagOption-\(tag.name)")
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(Text(isSelected ? "已选中" : ""))
    }

    private var allMoodChip: some View {
        let isSelected = selectedMood == nil
        return Button {
            clearMoodFilter()
        } label: {
            HStack(spacing: 6) {
                Text("全部心情")
                    .font(AppTypography.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                }
            }
            .foregroundStyle(isSelected ? theme.onAccentText : theme.primaryText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 10)
            .background {
                Capsule()
                    .fill(isSelected ? theme.accent : theme.chipFill)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filterMoodOption-all")
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(Text(isSelected ? "已选中" : ""))
    }

    private func moodChip(_ mood: Mood) -> some View {
        let isSelected = selectedMood == mood
        return Button {
            toggleMood(mood)
        } label: {
            HStack(spacing: 6) {
                Text(mood.emoji)
                Text(mood.displayName)
                    .font(AppTypography.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                }
            }
            .foregroundStyle(isSelected ? theme.onAccentText : theme.primaryText)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 10)
            .background {
                Capsule()
                    .fill(isSelected ? theme.accent : theme.chipFill)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filterMoodOption-\(mood.rawValue)")
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(Text(isSelected ? "已选中" : ""))
    }

    /// 点已选标签取消该项，点未选标签追加（多选累加，见 04 §4.2）。
    private func toggleTag(_ tagID: UUID) {
        var updated = activeFilter ?? FilterCondition()
        if updated.tagIDs.contains(tagID) {
            updated.tagIDs.remove(tagID)
        } else {
            updated.tagIDs.insert(tagID)
        }
        activeFilter = updated.isEmpty ? nil : updated
    }

    /// 显式回到「全部心情」：只清除心情维度，保留已选标签。
    private func clearMoodFilter() {
        guard var updated = activeFilter else { return }
        updated.mood = nil
        activeFilter = updated.isEmpty ? nil : updated
    }

    /// 心情单选：点已选项取消（回到未选心情），点其它项切换选中（同一时间至多一个）。
    private func toggleMood(_ mood: Mood) {
        var updated = activeFilter ?? FilterCondition()
        updated.mood = (updated.mood == mood) ? nil : mood
        activeFilter = updated.isEmpty ? nil : updated
    }
}

#Preview {
    FilterPanelView(activeFilter: .constant(nil))
        .environment(ThemeManager())
        // swiftlint:disable:next force_try
        .modelContainer(try! ModelContainerConfig.makeInMemoryContainer())
}
