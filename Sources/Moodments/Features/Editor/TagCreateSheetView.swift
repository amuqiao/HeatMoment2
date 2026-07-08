import SwiftData
import SwiftUI

/// 新建/重命名标签任务卡片（见 `docs/design/04-screen-specs.md` §4.7/§4.13）：任务卡片栈的
/// 第二层（从 `TagManageView` 打开，见 08-architecture.md §2.2），供标签管理新增/重命名
/// 共用同一实现（阶段6：`editing` 非 `nil` 即重命名态，预填原名）。
///
/// **创建态**：保存时应用层查重（`TagRepository.findTag(named:)`，CloudKit 不支持 `.unique`，
/// 见 07-data-persistence.md §2）——命中已存在同名标签则直接复用回填，不重复创建；未命中先复核
/// 标签额度，仍允许时才新建。
/// **重命名态**：保存分流到 `TagRepository.renameTag(id:newName:)`（应用层查重撞名抛
/// `tagNameConflict`）。空输入禁用保存；写失败改走统一 `ErrorPresenter`（用户可见、不中止进程、
/// 不 dismiss——保留输入内容供重试，见阶段6计划决策3）。
struct TagCreateSheetView: View {
    let modelContainer: ModelContainer
    /// 非 `nil` 表示重命名既有标签（预填其原名）；`nil` 表示新建。
    var editing: TagSnapshot?
    /// 新建（或查重复用的既有）标签 / 重命名成功后的回填回调，统一传回 `(id, 最终名称)`。
    let onCreated: (UUID, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(SubscriptionService.self) private var subscriptionService
    @State private var name: String
    @State private var isSaving = false
    @State private var paywallTrigger: PaywallTrigger?

    init(
        modelContainer: ModelContainer, editing: TagSnapshot? = nil,
        onCreated: @escaping (UUID, String) -> Void
    ) {
        self.modelContainer = modelContainer
        self.editing = editing
        self.onCreated = onCreated
        _name = State(initialValue: editing?.name ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                form
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height, alignment: .center)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.sheetBackground.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(theme.sheetBackground)
        .sheet(item: $paywallTrigger) { trigger in
            ProPaywallView(trigger: trigger)
        }
        // 本视图是任务卡片栈第二层、可能的最前 sheet（从 `TagManageView` 弹出）：
        // `.alert` 不跨 sheet 边界，父级（`SettingsSheetView`）挂的
        // `.userFacingErrorAlert` 弹不到本层之上，故本视图需自行挂一份，绑定同一份经
        // `@Environment` 注入的共享 `ErrorPresenter`（见 `UserFacingErrorAlert.swift` 头部说明）。
        .userFacingErrorAlert(errorPresenter)
    }

    private var form: some View {
        VStack(spacing: 28) {
            title

            TextField("输入新的标签名", text: $name)
                .font(AppTypography.body)
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.chipFill)
                )
                .accessibilityIdentifier("tagCreateNameField")
                .accessibilityLabel(Text("标签名称输入框"))

            VStack(spacing: 26) {
                Button {
                    Task { await save() }
                } label: {
                    Text("保存")
                        .font(AppTypography.button)
                        .foregroundStyle(theme.onAccentText)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(saveButtonFill)
                        )
                }
                .buttonStyle(.plain)
                .disabled(trimmedName.isEmpty || isSaving)
                .accessibilityIdentifier("tagCreateSaveButton")
                .accessibilityHint(Text(trimmedName.isEmpty ? "标签名称为空时不可保存" : ""))

                Button("取消") { dismiss() }
                    .font(AppTypography.button)
                    .foregroundStyle(theme.primaryText)
                    .accessibilityIdentifier("tagCreateCancelButton")
            }
        }
    }

    private var title: some View {
        HStack(spacing: 12) {
            Text("#")
                .font(.title3.weight(.bold))
                .foregroundStyle(theme.sheetBackground)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.secondaryText)
                )

            Text(editing == nil ? "标签名称" : "重命名标签")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.primaryText)
                .accessibilityIdentifier("tagCreateTitleText")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(editing == nil ? "# 标签名称" : "# 重命名标签"))
    }

    private var saveButtonFill: Color {
        trimmedName.isEmpty || isSaving ? theme.accentDisabledFill : theme.accent
    }

    private func save() async {
        guard !trimmedName.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        let repository = TagRepository(modelContainer: modelContainer)
        do {
            if let editing {
                try await repository.renameTag(id: editing.id, newName: trimmedName)
                onCreated(editing.id, trimmedName)
                dismiss()
                return
            }
            if let existing = try await repository.findTag(named: trimmedName) {
                onCreated(existing.id, existing.name)
                dismiss()
                return
            }
            guard try await canCreateTag(repository: repository) else {
                paywallTrigger = .quotaTag
                return
            }
            let id = try await repository.createTag(name: trimmedName)
            onCreated(id, trimmedName)
            dismiss()
        } catch RepositoryError.tagNameConflict(let conflictingName) {
            await errorPresenter.report(
                message: "标签名「\(conflictingName)」已存在，请换一个名称。",
                underlying: RepositoryError.tagNameConflict(conflictingName)
            )
        } catch {
            let message: String.LocalizationValue =
                editing == nil ? "创建标签失败，请稍后重试。" : "重命名标签失败，请稍后重试。"
            await errorPresenter.report(message: message, underlying: error)
        }
    }

    private func canCreateTag(repository: TagRepository) async throws -> Bool {
        let count = try await repository.totalTagCount()
        let isPro = await subscriptionService.currentEntitlementIsPro()
        let quotaService = QuotaService(
            entitlementProvider: SubscriptionEntitlementProvider(isPro: isPro)
        )
        return quotaService.checkCanCreateTag(currentTagCount: count) == .allowed
    }
}
