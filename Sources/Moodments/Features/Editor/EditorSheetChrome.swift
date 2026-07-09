import SwiftUI

struct EditorSheetChrome<Center: View>: View {
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder let center: Center

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: EditorLayout.chromeItemSpacing) {
            Button("取消", action: onCancel)
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .frame(width: EditorLayout.chromeActionSlotWidth, alignment: .leading)
                .accessibilityIdentifier("editorCancelButton")

            HStack(spacing: EditorLayout.chromeItemSpacing) {
                center
            }
            .frame(maxWidth: .infinity)

            Button("保存", action: onSave)
                .foregroundStyle(theme.accent)
                .fontWeight(.semibold)
                .disabled(!canSave)
                .lineLimit(1)
                .frame(width: EditorLayout.chromeActionSlotWidth, alignment: .trailing)
                .accessibilityIdentifier("editorSaveButton")
        }
        .font(AppTypography.body)
        .padding(.horizontal, EditorLayout.chromeHorizontalPadding)
        .padding(.vertical, EditorLayout.chromeVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: EditorLayout.chromeMinHeight)
        .background(theme.sheetBackground)
    }
}
