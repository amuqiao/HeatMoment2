import SwiftData
import SwiftUI

/// 标签/心情筛选就近浮窗（见 `docs/design/04-screen-specs.md` §4.2）：从首页收起态标题
/// 「时刻 ⌄」锚点旁弹出，背景不下沉、不入层级栈（依 ADR-006）。
///
/// **筛选组合逻辑**（已裁决，见 04 §4.2、`docs/design/13-open-questions.md` #19）：标签
/// **多选**、彼此 **AND**（交集）；心情**单选**；标签维度与心情维度之间也是 AND。
/// 每次点选**即时更新** `activeFilter`（就地生效，无「确认」按钮），标签支持多选故面板
/// 不因单次点选而关闭；点浮窗外部收起由调用方 `.popover` 自身负责，本视图不持有呈现状态。
struct FilterPanelView: View {
    @Binding var activeFilter: FilterCondition?

    @Environment(ThemeManager.self) private var theme
    @Query(sort: \Tag.createdAt) private var tags: [Tag]

    private var selectedTagIDs: Set<UUID> { activeFilter?.tagIDs ?? [] }
    private var selectedMood: Mood? { activeFilter?.mood }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tags.isEmpty {
                Text("还没有标签，先去标签管理创建一个吧")
                    .font(AppTypography.caption)
                    .foregroundStyle(theme.bubbleBodyText)
                    .padding(16)
                    .accessibilityIdentifier("filterNoTagsHint")
            } else {
                ForEach(tags) { tag in
                    tagRow(tag)
                }
                Divider()
            }

            ForEach(Mood.allCases) { mood in
                moodRow(mood)
            }
        }
        .frame(width: 260)
        .fixedSize(horizontal: false, vertical: true)
        .background(theme.sheetBackground)
    }

    private func tagRow(_ tag: Tag) -> some View {
        let isSelected = selectedTagIDs.contains(tag.id)
        return Button {
            toggleTag(tag.id)
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
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(isSelected ? theme.accent.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filterTagOption-\(tag.name)")
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(Text(isSelected ? "已选中" : ""))
    }

    private func moodRow(_ mood: Mood) -> some View {
        let isSelected = selectedMood == mood
        return Button {
            toggleMood(mood)
        } label: {
            HStack {
                Text(mood.emoji)
                Text(mood.displayName)
                    .foregroundStyle(theme.primaryText)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.primaryText)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(isSelected ? theme.accent.opacity(0.08) : Color.clear)
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
