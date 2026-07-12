import SwiftUI

struct MomentEditorHeaderBar: View {
    let layout: MomentEditorLayoutMetrics
    let isLoaded: Bool
    let cancellation: AppSheetAction
    let confirmation: AppSheetAction
    @Binding var occurredAt: Date
    @Binding var isDatePickerPresented: Bool
    @Binding var isTimePickerPresented: Bool

    var body: some View {
        AppSheetHeaderBar(
            cancellation: cancellation,
            confirmation: confirmation,
            metrics: AppSheetHeaderMetrics(
                horizontalPadding: layout.topChromeHorizontalPadding,
                verticalPadding: layout.topChromeVerticalPadding,
                minHeight: layout.topChromeMinHeight,
                actionSlotWidth: layout.topChromeActionSlotWidth,
                itemSpacing: layout.topChromeItemSpacing
            ),
            accessibilityIdentifier: "editorHeaderBar"
        ) {
            MomentEditorTopChrome(
                layout: layout,
                isLoaded: isLoaded,
                occurredAt: $occurredAt,
                isDatePickerPresented: $isDatePickerPresented,
                isTimePickerPresented: $isTimePickerPresented
            )
        }
    }
}
