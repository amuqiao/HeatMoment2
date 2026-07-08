import SwiftUI

/// Settings-flow navigation chrome stays on system components: root pages keep the
/// default title style, while pushed detail pages use an inline centered title.
extension View {
    func settingsRootNavigationChrome(_ title: LocalizedStringKey) -> some View {
        navigationTitle(title)
            .settingsNavigationBarScrollEdge()
    }

    func settingsDetailNavigationChrome(_ title: LocalizedStringKey) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .settingsNavigationBarScrollEdge()
    }

    private func settingsNavigationBarScrollEdge() -> some View {
        toolbarBackground(.automatic, for: .navigationBar)
    }
}
