import SwiftData
import SwiftUI

/// 标签/心情筛选面板（见 `docs/design/04-screen-specs.md` §4.2）：从首页收起态标题
/// 「时刻 ⌄」升起的**半屏 bottom sheet**（交互模型 v2 修订，见 ADR-006 `[AMENDED v2]`——
/// 筛选从就近浮窗 popover 解耦为 `.presentationDetents([.medium, .large])` 的 sheet，因其
/// 要同时承载心情单选 + 标签多选 + 新增标签入口，条目多、popover 里会拥挤）。呈现容器改变，
/// 但筛选其余性质不变：**不进 `AppRouter`**、由触发处局部 `@State` 驱动、就地即时生效。
///
/// **筛选组合逻辑**（已裁决，见 04 §4.2、`docs/design/13-open-questions.md` #19）：标签
/// **多选**、彼此 **AND**（交集）；心情**单选**；标签维度与心情维度之间也是 AND。
/// 每次点选**即时更新** `activeFilter`（就地生效，无「确认」按钮）；「完成」仅收起 sheet、
/// 不做提交。标签区末尾「+ 新增标签」唤起 `TagCreateSheetView` 第二层 sheet，创建成功后把
/// 新标签 id 自动并入 `activeFilter.tagIDs`（立即可筛）。
///
/// **布局取舍（标签区在前）**：把「标签」区放在「心情」区之前——半屏 `.medium` detent 下
/// `List` 是惰性渲染，靠后的行未滚入视口时不入无障碍树。既有 UI 验收会在半高 sheet 内直接点
/// `filterTagOption-工作`（TagManage）与 `filterMoodOption-1`（LocateFilter/TitleCollapse），
/// 标签区（默认 3 个预置标签）在前可让二者都落在首屏可见/可命中范围内，避免依赖 sheet 展开。
struct FilterPanelView: View {
    @Binding var activeFilter: FilterCondition?

    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.createdAt) private var tags: [Tag]

    @State private var isAddTagPresented = false

    private var selectedTagIDs: Set<UUID> { activeFilter?.tagIDs ?? [] }
    private var selectedMood: Mood? { activeFilter?.mood }

    var body: some View {
        NavigationStack {
            List {
                Section("标签") {
                    if tags.isEmpty {
                        Text("还没有标签，点下方「新增标签」创建一个吧")
                            .font(AppTypography.caption)
                            .foregroundStyle(theme.bubbleBodyText)
                            .accessibilityIdentifier("filterNoTagsHint")
                    } else {
                        ForEach(tags) { tag in
                            tagRow(tag)
                        }
                    }
                    addTagButton
                }

                Section("心情") {
                    ForEach(Mood.allCases) { mood in
                        moodRow(mood)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("filterDoneButton")
                }
            }
            .sheet(isPresented: $isAddTagPresented) {
                // 第二层 sheet：新建标签任务卡片，复用编辑器/标签管理同一实现。创建成功回填
                // `(id, _)` 后把新标签 id 并入筛选条件（立即可筛，无需再手动勾选）。
                TagCreateSheetView(modelContainer: modelContext.container) { id, _ in
                    addTagToFilter(id)
                }
            }
        }
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
                        .foregroundStyle(theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filterTagOption-\(tag.name)")
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(Text(isSelected ? "已选中" : ""))
    }

    private var addTagButton: some View {
        Button {
            isAddTagPresented = true
        } label: {
            Label("新增标签", systemImage: "plus")
                .foregroundStyle(theme.accent)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filterAddTagButton")
        .accessibilityAddTraits(.isButton)
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
                        .foregroundStyle(theme.accent)
                }
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

    /// 心情单选：点已选项取消（回到未选心情），点其它项切换选中（同一时间至多一个）。
    private func toggleMood(_ mood: Mood) {
        var updated = activeFilter ?? FilterCondition()
        updated.mood = (updated.mood == mood) ? nil : mood
        activeFilter = updated.isEmpty ? nil : updated
    }

    /// 新建标签成功回填：把新标签 id 并入当前筛选条件，立即可筛（见 04 §4.2「新增标签子级 sheet」）。
    private func addTagToFilter(_ tagID: UUID) {
        var updated = activeFilter ?? FilterCondition()
        updated.tagIDs.insert(tagID)
        activeFilter = updated.isEmpty ? nil : updated
    }
}

#Preview {
    FilterPanelView(activeFilter: .constant(nil))
        .environment(ThemeManager())
        // swiftlint:disable:next force_try
        .modelContainer(try! ModelContainerConfig.makeInMemoryContainer())
}
