import SwiftUI

struct MomentEditorHeaderBar: View {
    let layout: MomentEditorLayoutMetrics
    let isLoaded: Bool
    let cancellation: TaskSheetAction
    let confirmation: TaskSheetAction
    @Binding var occurredAt: Date
    @Binding var isDatePickerPresented: Bool
    @Binding var isTimePickerPresented: Bool

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: layout.topChromeItemSpacing) {
            taskSheetButton(cancellation)
                .foregroundStyle(theme.accent)
                .frame(width: layout.topChromeActionSlotWidth, alignment: .leading)

            MomentEditorTopChrome(
                layout: layout,
                isLoaded: isLoaded,
                occurredAt: $occurredAt,
                isDatePickerPresented: $isDatePickerPresented,
                isTimePickerPresented: $isTimePickerPresented
            )
            .frame(maxWidth: .infinity)

            taskSheetButton(confirmation)
                .foregroundStyle(theme.accent)
                .frame(width: layout.topChromeActionSlotWidth, alignment: .trailing)
        }
        .font(AppTypography.body)
        .padding(.horizontal, layout.topChromeHorizontalPadding)
        .padding(.vertical, layout.topChromeVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: layout.topChromeMinHeight)
        .background(theme.sheetBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editorHeaderBar")
    }

    @ViewBuilder
    private func taskSheetButton(_ action: TaskSheetAction) -> some View {
        let button = Button(role: action.role, action: action.handler) {
            Text(action.title)
        }
        .fontWeight(action.isProminent ? .semibold : .regular)
        .disabled(action.isDisabled)
        .lineLimit(1)

        if let accessibilityIdentifier = action.accessibilityIdentifier {
            button.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            button
        }
    }
}
