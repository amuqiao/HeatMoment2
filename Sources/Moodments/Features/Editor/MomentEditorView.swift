import SwiftData
import SwiftUI

/// 「上次选择情绪」持久化 key（见阶段 3 计划决策5：`@AppStorage` 本地持久化，
/// 03-user-flows.md §3.1：有历史选择则用上次选择，否则回退 `Mood.normal`）。
enum EditorMoodMemory {
    static let storageKey = "com.moodments.lastUsedMood"
}

/// 新建/编辑一条时刻（任务卡片栈，见 `docs/design/04-screen-specs.md` §4.4、
/// `docs/design/03-user-flows.md` §3.1、`docs/design/08-architecture.md` §2.2）。
///
/// 情绪/标签/日期/时间选择均为**就近浮窗**（局部 `@State` 驱动，不进 `AppRouter`，依 ADR-006）；
/// 标签选择只消费已有标签。标签新增、重命名、删除归属设置页 `TagManageView`。
struct MomentEditorView: View {
    let mode: EditorMode
    let modelContainer: ModelContainer

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(SyncStatusService.self) private var syncStatusService
    @AppStorage(EditorMoodMemory.storageKey) private var lastUsedMood: Mood = .normal

    @State private var model: MomentEditorModel
    @State private var isMoodPickerPresented = false
    @State private var isTagPickerPresented = false
    @State private var isDatePickerPresented = false
    @State private var isTimePickerPresented = false
    @State private var isDiscardAlertPresented = false
    @State private var editorPaywallTrigger: PaywallTrigger?

    /// `subscriptionService` 由调用方（`RootView`）经 `@Environment(SubscriptionService.self)`
    /// 读出后显式传入，而非在本视图内部再读一次 `@Environment`——`init()` 内需要立即构造
    /// `MomentEditorModel`（草稿模型），而 `@Environment` 属性包装器只在视图挂载后才解析，
    /// `init()` 阶段读取会拿到默认/未初始化状态（与 `lastUsedMood` 需要绕开
    /// `@AppStorage` 初始化顺序陷阱同一原因，见下方注释）。
    init(mode: EditorMode, modelContainer: ModelContainer, subscriptionService: SubscriptionService)
    {
        self.mode = mode
        self.modelContainer = modelContainer
        // 直接读 `UserDefaults` 而非 `_lastUsedMood` 的 wrapped value：属性包装器初始化顺序
        // 不保证此刻可跨属性引用 `self`，故用同一 key 的原始读取规避该顺序陷阱；二者读写
        // 同一 UserDefaults key，语义一致。缺省值 0 恰好等于 `Mood.normal.rawValue`，与
        // 「无历史选择回退到 .normal」的产品规则天然吻合（见阶段 3 计划决策5）。
        let seedMood =
            Mood(rawValue: UserDefaults.standard.integer(forKey: EditorMoodMemory.storageKey))
            ?? .normal
        _model = State(
            initialValue: MomentEditorModel(
                mode: mode, modelContainer: modelContainer,
                subscriptionService: subscriptionService, lastUsedMood: seedMood
            ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoaded {
                    content
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(theme.sheetBackground.ignoresSafeArea())
            .toolbar { toolbarContent }
            .alert("放弃编辑？", isPresented: $isDiscardAlertPresented) {
                Button("放弃编辑", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            }
            .sheet(item: $editorPaywallTrigger) { trigger in
                ProPaywallView(trigger: trigger)
            }
            .userFacingErrorAlert(errorPresenter)
        }
        .themedTaskContainer(theme)
        .task {
            guard case .edit = mode else { return }
            do {
                try await model.load()
            } catch {
                await errorPresenter.report(message: "加载时刻失败，请稍后重试。", underlying: error)
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                moodAndTagRow
                Divider()
                titleField
                Divider()
                bodyField
                EditorPhotoSection(model: model, editorPaywallTrigger: $editorPaywallTrigger)
            }
            .padding(20)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { handleCancel() }
                .accessibilityIdentifier("editorCancelButton")
        }
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                dateChip
                timeChip
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("保存") { handleSave() }
                .foregroundStyle(theme.accent)
                .fontWeight(.semibold)
                .disabled(!model.canSave)
                .accessibilityIdentifier("editorSaveButton")
        }
    }

    // MARK: - 情绪 + 标签行（同一行左右布局，见 05-design-system.md §5.7）

    private var moodAndTagRow: some View {
        HStack {
            moodButton
            Spacer()
            tagButton
        }
    }

    private var moodButton: some View {
        Button {
            isMoodPickerPresented = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill").foregroundStyle(theme.accent)
                Text("\(model.mood.emoji) \(model.mood.displayName)")
                    .foregroundStyle(theme.primaryText)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .accessibilityIdentifier("editorMoodRow")
        .accessibilityLabel(Text("情绪，\(model.mood.displayName)，双击更改"))
        .popover(isPresented: $isMoodPickerPresented, arrowEdge: .top) {
            MoodPickerView(selectedMood: model.mood) { mood in
                model.mood = mood
                isMoodPickerPresented = false
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    private var tagButton: some View {
        Button {
            isTagPickerPresented = true
        } label: {
            HStack(spacing: 4) {
                Text("#").foregroundStyle(theme.accent)
                Text(tagSummaryText).foregroundStyle(theme.primaryText)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .accessibilityIdentifier("editorTagRow")
        .accessibilityLabel(Text("标签，\(tagSummaryText)，双击更改"))
        .popover(isPresented: $isTagPickerPresented, arrowEdge: .top) {
            TagPickerView(
                modelContainer: modelContainer,
                selectedTagIDs: model.selectedTagIDs,
                onToggle: { tag in model.toggleTagSelection(tag) }
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var tagSummaryText: String {
        guard !model.selectedTagIDs.isEmpty else {
            return LanguagePreference.localizedString("选择标签")
        }
        return model.selectedTagIDs.compactMap { model.tagNamesByID[$0] }.joined(separator: " ")
    }

    // MARK: - 日期 / 时间 chip（见 04-screen-specs.md §4.4/§4.8）

    private var dateChip: some View {
        Button {
            isDatePickerPresented = true
        } label: {
            Text(dateChipText)
                .font(AppTypography.body)
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(theme.chipFill))
        }
        .accessibilityIdentifier("editorDateChip")
        .popover(isPresented: $isDatePickerPresented, arrowEdge: .top) {
            DatePickerSheetView(
                occurredAt: Binding(get: { model.occurredAt }, set: { model.occurredAt = $0 })
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var timeChip: some View {
        Button {
            isTimePickerPresented = true
        } label: {
            Text(timeChipText)
                .font(AppTypography.body)
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(theme.chipFill))
        }
        .accessibilityIdentifier("editorTimeChip")
        .popover(isPresented: $isTimePickerPresented, arrowEdge: .top) {
            TimePickerSheetView(
                occurredAt: Binding(get: { model.occurredAt }, set: { model.occurredAt = $0 })
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var dateChipText: String { Self.dateFormatter.string(from: model.occurredAt) }
    private var timeChipText: String { Self.timeFormatter.string(from: model.occurredAt) }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    // MARK: - 标题 / 正文

    private var titleField: some View {
        TextField("标题", text: titleBinding)
            .font(AppTypography.cardTitle)
            .foregroundStyle(theme.primaryText)
            .accessibilityIdentifier("editorTitleField")
    }

    private var bodyField: some View {
        TextField("正文", text: bodyBinding, axis: .vertical)
            .font(AppTypography.body)
            .foregroundStyle(theme.primaryText)
            .lineLimit(5...12)
            .accessibilityIdentifier("editorBodyField")
    }

    private var titleBinding: Binding<String> {
        Binding(get: { model.title }, set: { model.title = $0 })
    }

    private var bodyBinding: Binding<String> {
        Binding(get: { model.bodyText }, set: { model.bodyText = $0 })
    }

    // MARK: - 取消 / 保存（见 03-user-flows.md §3.1）

    private func handleCancel() {
        if model.isDirty {
            isDiscardAlertPresented = true
        } else {
            dismiss()
        }
    }

    private func handleSave() {
        guard model.canSave else { return }
        Task {
            do {
                try await model.save()
                // 保存成功即一次本地写入，驱动设置页 iCloud 行短暂展示「同步中」三态
                // （见 `SyncStatusService.noteLocalWrite()` 头部说明，阶段7 review 建议9）。
                syncStatusService.noteLocalWrite()
                if case .create = mode {
                    lastUsedMood = model.mood
                }
                dismiss()
            } catch {
                // 保存失败不 dismiss——草稿留在编辑器内供用户重试，不假装保存成功
                // （见阶段6计划决策3：可恢复写失败改走统一错误通道，不伪造成功）。
                await errorPresenter.report(message: "保存时刻失败，请稍后重试。", underlying: error)
            }
        }
    }

}

#Preview {
    // swiftlint:disable:next force_try
    let container = try! ModelContainerConfig.makeInMemoryContainer()
    return MomentEditorView(
        mode: .create, modelContainer: container, subscriptionService: SubscriptionService()
    )
    .environment(ThemeManager())
    .environment(ErrorPresenter())
    .environment(SyncStatusService(cloudKitEnabled: false))
}
