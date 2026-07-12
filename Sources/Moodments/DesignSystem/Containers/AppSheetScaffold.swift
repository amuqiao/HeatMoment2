import SwiftUI

enum AppSheetStyle {
    case standard
    case commercial

    @MainActor
    func background(_ theme: ThemeManager) -> Color {
        switch self {
        case .standard: theme.sheetBackground
        case .commercial: theme.commercialBackground
        }
    }

    @MainActor
    func tint(_ theme: ThemeManager) -> Color {
        switch self {
        case .standard: theme.accent
        case .commercial: theme.commercialRed
        }
    }

    @MainActor
    func colorScheme(_ theme: ThemeManager) -> ColorScheme {
        switch self {
        case .standard: theme.mode.colorScheme
        case .commercial: .light
        }
    }
}

private struct AppSheetStyleEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppSheetStyle = .standard
}

extension EnvironmentValues {
    var appSheetStyle: AppSheetStyle {
        get { self[AppSheetStyleEnvironmentKey.self] }
        set { self[AppSheetStyleEnvironmentKey.self] = newValue }
    }
}

struct AppSheetScaffold<Content: View>: View {
    @Environment(ThemeManager.self) private var theme

    private let style: AppSheetStyle
    private let hidesSystemNavigationBar: Bool
    @ViewBuilder private let content: Content

    init(
        style: AppSheetStyle = .standard,
        hidesSystemNavigationBar: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.hidesSystemNavigationBar = hidesSystemNavigationBar
        self.content = content()
    }

    var body: some View {
        let colorScheme = style.colorScheme(theme)
        let background = style.background(theme)

        NavigationStack {
            content
                .background(background.ignoresSafeArea())
                .toolbar(hidesSystemNavigationBar ? .hidden : .automatic, for: .navigationBar)
        }
        .environment(\.appSheetStyle, style)
        .environment(\.colorScheme, colorScheme)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .tint(style.tint(theme))
        .presentationBackground(background)
    }
}

struct AppSheetHeaderBar<Principal: View>: View {
    let cancellation: AppSheetAction?
    let confirmation: AppSheetAction?
    let metrics: AppSheetHeaderMetrics
    let accessibilityIdentifier: String?
    @ViewBuilder let principal: Principal

    @Environment(ThemeManager.self) private var theme
    @Environment(\.appSheetStyle) private var style

    init(
        cancellation: AppSheetAction? = nil,
        confirmation: AppSheetAction? = nil,
        metrics: AppSheetHeaderMetrics = .standard,
        accessibilityIdentifier: String? = nil,
        @ViewBuilder principal: () -> Principal
    ) {
        self.cancellation = cancellation
        self.confirmation = confirmation
        self.metrics = metrics
        self.accessibilityIdentifier = accessibilityIdentifier
        self.principal = principal()
    }

    var body: some View {
        HStack(spacing: metrics.itemSpacing) {
            actionSlot(cancellation, alignment: .leading)

            HStack(spacing: metrics.itemSpacing) {
                principal
            }
            .frame(maxWidth: .infinity)

            actionSlot(confirmation, alignment: .trailing)
        }
        .font(AppTypography.body)
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .frame(maxWidth: .infinity, minHeight: metrics.minHeight)
        .background(style.background(theme))
        .accessibilityElement(children: .contain)
        .applyOptionalAccessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private func actionSlot(
        _ action: AppSheetAction?,
        alignment: Alignment
    ) -> some View {
        if let action {
            AppSheetActionButton(action)
                .frame(width: metrics.actionSlotWidth, alignment: alignment)
        } else {
            Color.clear
                .frame(width: metrics.actionSlotWidth)
                .accessibilityHidden(true)
        }
    }
}

struct AppSheetHeaderMetrics: Equatable {
    static let standard = AppSheetHeaderMetrics()

    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let minHeight: CGFloat
    let actionSlotWidth: CGFloat
    let itemSpacing: CGFloat

    init(
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 10,
        minHeight: CGFloat = 56,
        actionSlotWidth: CGFloat = 64,
        itemSpacing: CGFloat = 8
    ) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.minHeight = minHeight
        self.actionSlotWidth = actionSlotWidth
        self.itemSpacing = itemSpacing
    }
}

struct AppSheetAction {
    let title: LocalizedStringKey
    let accessibilityIdentifier: String?
    let role: ButtonRole?
    let isDisabled: Bool
    let isProminent: Bool
    let handler: () -> Void

    init(
        _ title: LocalizedStringKey,
        accessibilityIdentifier: String? = nil,
        role: ButtonRole? = nil,
        isDisabled: Bool = false,
        isProminent: Bool = false,
        handler: @escaping () -> Void
    ) {
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.role = role
        self.isDisabled = isDisabled
        self.isProminent = isProminent
        self.handler = handler
    }
}

struct AppSheetActionButton: View {
    let action: AppSheetAction

    @Environment(ThemeManager.self) private var theme
    @Environment(\.appSheetStyle) private var style

    init(_ action: AppSheetAction) {
        self.action = action
    }

    var body: some View {
        Button(role: action.role, action: action.handler) {
            Text(action.title)
        }
        .fontWeight(action.isProminent ? .semibold : .regular)
        .foregroundStyle(foregroundColor)
        .disabled(action.isDisabled)
        .lineLimit(1)
        .applyOptionalAccessibilityIdentifier(action.accessibilityIdentifier)
    }

    private var foregroundColor: Color {
        if action.role == .destructive {
            return theme.danger
        }
        return style.tint(theme)
    }
}

extension View {
    func appSheetChrome(
        title: LocalizedStringKey? = nil,
        titleDisplayMode: NavigationBarItem.TitleDisplayMode = .inline,
        cancellation: AppSheetAction? = nil,
        confirmation: AppSheetAction? = nil
    ) -> some View {
        modifier(
            AppSheetChromeModifier(
                title: title,
                titleDisplayMode: titleDisplayMode,
                cancellation: cancellation,
                confirmation: confirmation,
                showsPrincipal: false
            ) {
                EmptyView()
            }
        )
    }

    func appSheetChrome<Principal: View>(
        title: LocalizedStringKey? = nil,
        titleDisplayMode: NavigationBarItem.TitleDisplayMode = .inline,
        cancellation: AppSheetAction? = nil,
        confirmation: AppSheetAction? = nil,
        @ViewBuilder principal: @escaping () -> Principal
    ) -> some View {
        modifier(
            AppSheetChromeModifier(
                title: title,
                titleDisplayMode: titleDisplayMode,
                cancellation: cancellation,
                confirmation: confirmation,
                showsPrincipal: true,
                principal: principal
            )
        )
    }
}

private struct AppSheetChromeModifier<Principal: View>: ViewModifier {
    let title: LocalizedStringKey?
    let titleDisplayMode: NavigationBarItem.TitleDisplayMode
    let cancellation: AppSheetAction?
    let confirmation: AppSheetAction?
    let showsPrincipal: Bool
    @ViewBuilder let principal: () -> Principal

    func body(content: Content) -> some View {
        content
            .modifier(AppSheetTitleModifier(title: title, titleDisplayMode: titleDisplayMode))
            .toolbar {
                if let cancellation {
                    ToolbarItem(placement: .cancellationAction) {
                        AppSheetActionButton(cancellation)
                    }
                }

                if showsPrincipal {
                    ToolbarItem(placement: .principal) {
                        principal()
                    }
                }

                if let confirmation {
                    ToolbarItem(placement: .confirmationAction) {
                        AppSheetActionButton(confirmation)
                    }
                }
            }
    }
}

private struct AppSheetTitleModifier: ViewModifier {
    let title: LocalizedStringKey?
    let titleDisplayMode: NavigationBarItem.TitleDisplayMode

    @ViewBuilder
    func body(content: Content) -> some View {
        if let title {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(titleDisplayMode)
        } else {
            content
        }
    }
}

private extension View {
    @ViewBuilder
    func applyOptionalAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}
