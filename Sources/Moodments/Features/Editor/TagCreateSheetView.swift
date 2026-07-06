import SwiftData
import SwiftUI

/// 新建标签任务卡片（见 `docs/design/04-screen-specs.md` §4.7）：任务卡片栈的第二层
/// （从 `TagPickerView` 打开，见 08-architecture.md §2.2），保存时应用层查重
/// （`TagRepository.findTag(named:)`，CloudKit 不支持 `.unique`，见 07-data-persistence.md §2）——
/// 命中已存在同名标签则直接复用回填，不重复创建；未命中才新建。空输入禁用保存。
struct TagCreateSheetView: View {
    let modelContainer: ModelContainer
    /// 新建（或查重复用的既有）标签创建完成后的回填回调。
    let onCreated: (UUID, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @State private var name = ""
    @State private var isSaving = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("# 标签名称")
                .font(.headline)
                .foregroundStyle(theme.primaryText)

            TextField("输入新的标签名", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("tagCreateNameField")
                .accessibilityLabel(Text("标签名称输入框"))

            HStack(spacing: 16) {
                Button("取消") { dismiss() }
                    .accessibilityIdentifier("tagCreateCancelButton")

                Spacer()

                Button("保存") {
                    Task { await save() }
                }
                .foregroundStyle(theme.accent)
                .disabled(trimmedName.isEmpty || isSaving)
                .accessibilityIdentifier("tagCreateSaveButton")
                .accessibilityHint(Text(trimmedName.isEmpty ? "标签名称为空时不可保存" : ""))
            }
        }
        .padding(24)
        .presentationDetents([.height(180)])
    }

    private func save() async {
        guard !trimmedName.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        let repository = TagRepository(modelContainer: modelContainer)
        do {
            if let existing = try await repository.findTag(named: trimmedName) {
                onCreated(existing.id, existing.name)
                dismiss()
                return
            }
            let id = try await repository.createTag(name: trimmedName)
            onCreated(id, trimmedName)
            dismiss()
        } catch {
            assertionFailure("创建标签失败：\(error)")
        }
    }
}
