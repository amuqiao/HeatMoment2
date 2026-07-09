import SwiftUI

struct MomentEditorTopChrome: View {
    let layout: MomentEditorLayoutMetrics
    let isLoaded: Bool
    let canSave: Bool
    @Binding var occurredAt: Date
    @Binding var isDatePickerPresented: Bool
    @Binding var isTimePickerPresented: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: layout.topChromeItemSpacing) {
            Button("取消", action: onCancel)
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .frame(width: layout.topChromeActionSlotWidth, alignment: .leading)
                .accessibilityIdentifier("editorCancelButton")

            HStack(spacing: layout.topChromeItemSpacing) {
                if isLoaded {
                    dateChip
                    timeChip
                }
            }
            .frame(maxWidth: .infinity)

            Button("保存", action: onSave)
                .fontWeight(.semibold)
                .foregroundStyle(isLoaded && canSave ? theme.accent : theme.secondaryText)
                .lineLimit(1)
                .disabled(!isLoaded || !canSave)
                .frame(width: layout.topChromeActionSlotWidth, alignment: .trailing)
                .accessibilityIdentifier("editorSaveButton")
        }
        .font(AppTypography.body)
        .padding(.horizontal, layout.topChromeHorizontalPadding)
        .padding(.vertical, layout.topChromeVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: layout.topChromeMinHeight)
        .background(theme.sheetBackground)
    }

    private var dateChip: some View {
        Button {
            isDatePickerPresented = true
        } label: {
            Text(EditorDateTimeFormatters.date.string(from: occurredAt))
                .font(AppTypography.body)
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, layout.dateTimeChipHorizontalPadding)
                .padding(.vertical, layout.dateTimeChipVerticalPadding)
                .background(Capsule().fill(theme.chipFill))
        }
        .accessibilityIdentifier("editorDateChip")
        .popover(isPresented: $isDatePickerPresented, arrowEdge: .top) {
            DatePickerSheetView(
                occurredAt: Binding(get: { occurredAt }, set: { occurredAt = $0 })
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var timeChip: some View {
        Button {
            isTimePickerPresented = true
        } label: {
            Text(EditorDateTimeFormatters.time.string(from: occurredAt))
                .font(AppTypography.body)
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, layout.dateTimeChipHorizontalPadding)
                .padding(.vertical, layout.dateTimeChipVerticalPadding)
                .background(Capsule().fill(theme.chipFill))
        }
        .accessibilityIdentifier("editorTimeChip")
        .popover(isPresented: $isTimePickerPresented, arrowEdge: .top) {
            TimePickerSheetView(
                occurredAt: Binding(get: { occurredAt }, set: { occurredAt = $0 })
            )
            .presentationCompactAdaptation(.popover)
        }
    }
}
