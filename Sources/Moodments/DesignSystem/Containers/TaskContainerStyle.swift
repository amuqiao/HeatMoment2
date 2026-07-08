import SwiftUI

extension ThemeMode {
    var colorScheme: ColorScheme {
        switch self {
        case .dark: .dark
        case .light: .light
        }
    }
}

extension View {
    /// Applies the app's task-container mode to SwiftUI/UIKit-backed controls inside sheets.
    func themedTaskContainer(_ theme: ThemeManager) -> some View {
        environment(\.colorScheme, theme.colorScheme)
            .toolbarColorScheme(theme.colorScheme, for: .navigationBar)
            .tint(theme.accent)
    }

    /// Standard grouped task page background.
    func taskGroupedListBackground(_ theme: ThemeManager) -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.sheetBackground.ignoresSafeArea())
    }

    /// Standard row/panel surface for grouped task pages.
    func taskGroupedRowBackground(_ theme: ThemeManager) -> some View {
        listRowBackground(theme.sheetPanelBackground)
    }
}
