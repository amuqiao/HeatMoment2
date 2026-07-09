import SwiftUI

struct MomentEditorTopChrome: View {
    let layout: MomentEditorLayoutMetrics
    let isLoaded: Bool
    @Binding var occurredAt: Date
    @Binding var isDatePickerPresented: Bool
    @Binding var isTimePickerPresented: Bool

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: layout.topChromeItemSpacing) {
            if isLoaded {
                dateChip
                timeChip
            }
        }
        .font(AppTypography.body)
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
