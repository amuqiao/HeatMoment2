import SwiftUI

/// Navigation chrome for sheet flows that keep SwiftUI's system navigation stack.
///
/// Root pages keep the default title style, while pushed detail pages use an
/// inline centered title. The navigation bar background stays automatic so the
/// system scroll-edge material can take over instead of being hand-painted.
extension View {
    func appSheetRootNavigationChrome(_ title: LocalizedStringKey) -> some View {
        navigationTitle(title)
            .appSheetNavigationBarScrollEdge()
    }

    func appSheetDetailNavigationChrome(_ title: LocalizedStringKey) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .appSheetNavigationBarScrollEdge()
    }

    private func appSheetNavigationBarScrollEdge() -> some View {
        toolbarBackground(.automatic, for: .navigationBar)
    }
}
