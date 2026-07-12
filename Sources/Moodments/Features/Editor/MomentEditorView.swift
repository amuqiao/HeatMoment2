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
    let canonicalService: CanonicalLibraryService

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(SyncStatusService.self) private var syncStatusService
    @Environment(\.canonicalRecoveryCoordinator) private var canonicalRecoveryCoordinator
    @AppStorage(EditorMoodMemory.storageKey) private var lastUsedMood: Mood = .normal

    @State private var model: MomentEditorModel
    @State private var isMoodPickerPresented = false
    @State private var isTagPickerPresented = false
    @State private var isDatePickerPresented = false
    @State private var isTimePickerPresented = false
    @State private var isDiscardAlertPresented = false
    @State private var editorPaywallTrigger: PaywallTrigger?
    @State private var isSaving = false

    /// `subscriptionService` 由调用方（`RootView`）经 `@Environment(SubscriptionService.self)`
    /// 读出后显式传入，而非在本视图内部再读一次 `@Environment`——`init()` 内需要立即构造
    /// `MomentEditorModel`（草稿模型），而 `@Environment` 属性包装器只在视图挂载后才解析，
    /// `init()` 阶段读取会拿到默认/未初始化状态（与 `lastUsedMood` 需要绕开
    /// `@AppStorage` 初始化顺序陷阱同一原因，见下方注释）。
    init(
        mode: EditorMode,
        canonicalService: CanonicalLibraryService,
        subscriptionService: SubscriptionService
    ) {
        self.mode = mode
        self.canonicalService = canonicalService
        // 直接读 `UserDefaults` 而非 `_lastUsedMood` 的 wrapped value：属性包装器初始化顺序
        // 不保证此刻可跨属性引用 `self`，故用同一 key 的原始读取规避该顺序陷阱；二者读写
        // 同一 UserDefaults key，语义一致。缺省值 0 恰好等于 `Mood.normal.rawValue`，与
        // 「无历史选择回退到 .normal」的产品规则天然吻合（见阶段 3 计划决策5）。
        let seedMood =
            Mood(rawValue: UserDefaults.standard.integer(forKey: EditorMoodMemory.storageKey))
            ?? .normal
        _model = State(
            initialValue: MomentEditorModel(
                mode: mode, canonicalService: canonicalService,
                subscriptionService: subscriptionService, lastUsedMood: seedMood
            ))
    }

    var body: some View {
        TaskSheetScaffold {
            editorRoot
        }
        .alert("放弃编辑？", isPresented: $isDiscardAlertPresented) {
            Button("放弃编辑", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        }
        .sheet(item: $editorPaywallTrigger) { trigger in
            ProPaywallView(trigger: trigger)
        }
        .userFacingErrorAlert(errorPresenter)
        .task {
            guard case .edit = mode else { return }
            do {
                try await model.load()
            } catch {
                errorPresenter.report(message: "加载时刻失败，请稍后重试。", underlying: error)
            }
        }
    }

    private var editorRoot: some View {
        GeometryReader { proxy in
            let layout = MomentEditorLayoutResolver.resolve(
                scale: TimelineResponsiveScale(viewportWidth: proxy.size.width)
            )

            VStack(spacing: 0) {
                MomentEditorHeaderBar(
                    layout: layout,
                    isLoaded: model.isLoaded,
                    cancellation: cancelAction,
                    confirmation: saveAction,
                    occurredAt: occurredAtBinding,
                    isDatePickerPresented: $isDatePickerPresented,
                    isTimePickerPresented: $isTimePickerPresented
                )
                if model.isLoaded {
                    editorScrollContent(layout: layout)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(theme.sheetBackground.ignoresSafeArea())
                }
            }
        }
    }

    private var cancelAction: TaskSheetAction {
        TaskSheetAction(
            "取消",
            accessibilityIdentifier: "editorCancelButton"
        ) {
            handleCancel()
        }
    }

    private var saveAction: TaskSheetAction {
        TaskSheetAction(
            "保存",
            accessibilityIdentifier: "editorSaveButton",
            isDisabled: !model.isLoaded || !model.canSave || isSaving,
            isProminent: true
        ) {
            handleSave()
        }
    }

    private func editorScrollContent(layout: MomentEditorLayoutMetrics) -> some View {
        ScrollView {
            TaskResponsiveContent(spacing: 0, contentInsets: layout.contentInsets) {
                VStack(alignment: .leading, spacing: 0) {
                    moodAndTagRow(layout: layout)
                    editorTextPanel(layout: layout)
                        .padding(.top, layout.selectorToTextPanelGap)
                    EditorPhotoSection(model: model, editorPaywallTrigger: $editorPaywallTrigger)
                        .padding(.top, layout.textPanelToPhotoSectionGap)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.sheetBackground.ignoresSafeArea())
    }

    // MARK: - 情绪 + 标签行（同一行左右布局，见 05-design-system.md §5.7）

    private func moodAndTagRow(layout: MomentEditorLayoutMetrics) -> some View {
        HStack(spacing: layout.selectorRowGap) {
            moodButton(layout: layout)
            tagButton(layout: layout)
        }
    }

    private func moodButton(layout: MomentEditorLayoutMetrics) -> some View {
        Button {
            isMoodPickerPresented = true
        } label: {
            EditorSelectorButton(layout: layout) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(theme.accent)
            } summary: {
                Text("\(model.mood.emoji) \(model.mood.displayName)")
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
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

    private func tagButton(layout: MomentEditorLayoutMetrics) -> some View {
        Button {
            isTagPickerPresented = true
        } label: {
            EditorSelectorButton(layout: layout) {
                Text("#")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(theme.accent)
            } summary: {
                EditorTagSelectionSummary(selectedNames: selectedTagNames, layout: layout)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("editorTagRow")
        .accessibilityLabel(Text("标签，\(tagSummaryText)，双击更改"))
        .popover(isPresented: $isTagPickerPresented, arrowEdge: .top) {
            TagPickerView(
                selectedTagIDs: model.selectedTagIDs,
                onToggle: { tag in model.toggleTagSelection(tag) }
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var selectedTagNames: [String] {
        model.selectedTagIDs.compactMap { model.tagNamesByID[$0] }
    }

    private var tagSummaryText: String {
        let selectedNames = selectedTagNames
        guard !selectedNames.isEmpty else {
            return LanguagePreference.localizedString("选择标签")
        }
        return selectedNames.joined(separator: " ")
    }

    // MARK: - 标题 / 正文

    private func editorTextPanel(layout: MomentEditorLayoutMetrics) -> some View {
        TaskSurfacePanel {
            VStack(alignment: .leading, spacing: layout.textPanelFieldSpacing) {
                titleField
                Divider()
                bodyField(layout: layout)
            }
        }
        .taskSurfaceMeasurementIdentifier("editorTextPanel")
    }

    private var titleField: some View {
        TextField("标题", text: titleBinding)
            .font(AppTypography.cardTitle)
            .foregroundStyle(theme.primaryText)
            .accessibilityIdentifier("editorTitleField")
    }

    private func bodyField(layout: MomentEditorLayoutMetrics) -> some View {
        TextField("正文", text: bodyBinding, axis: .vertical)
            .font(AppTypography.body)
            .foregroundStyle(theme.primaryText)
            .lineLimit(5...8)
            .frame(minHeight: layout.bodyMinHeight, alignment: .topLeading)
            .accessibilityIdentifier("editorBodyField")
    }

    private var titleBinding: Binding<String> {
        Binding(get: { model.title }, set: { model.title = $0 })
    }

    private var bodyBinding: Binding<String> {
        Binding(get: { model.bodyText }, set: { model.bodyText = $0 })
    }

    private var occurredAtBinding: Binding<Date> {
        Binding(get: { model.occurredAt }, set: { model.occurredAt = $0 })
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
        guard model.canSave, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await model.save(using: mutationService)
                if case .create = mode {
                    lastUsedMood = model.mood
                }
                dismiss()
            } catch LocalLibraryMutationError.quotaExceeded(.moments) {
                editorPaywallTrigger = .quotaMoment
            } catch {
                // 保存失败不 dismiss——草稿留在编辑器内供用户重试，不假装保存成功
                // （见阶段6计划决策3：可恢复写失败改走统一错误通道，不伪造成功）。
                errorPresenter.report(message: "保存时刻失败，请稍后重试。", underlying: error)
            }
        }
    }

    private var mutationService: LocalLibraryMutationService {
        LocalLibraryMutationService(
            canonicalService: canonicalService,
            canonicalRecoveryCoordinator: canonicalRecoveryCoordinator,
            syncStatusService: syncStatusService,
            errorPresenter: errorPresenter
        )
    }

}

#Preview {
    // swiftlint:disable:next force_try
    let canonicalService = try! CanonicalLibraryService(runtime: .makeInMemoryForTests())
    return MomentEditorView(
        mode: .create, canonicalService: canonicalService,
        subscriptionService: SubscriptionService()
    )
    .environment(ThemeManager())
    .environment(ErrorPresenter())
    .environment(SyncStatusService(cloudKitEnabled: false))
}
