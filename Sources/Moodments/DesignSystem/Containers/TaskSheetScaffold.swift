import SwiftUI

enum TaskSheetStyle {
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

struct TaskSheetScaffold<Content: View>: View {
    @Environment(ThemeManager.self) private var theme

    private let style: TaskSheetStyle
    @ViewBuilder private let content: Content

    init(style: TaskSheetStyle = .standard, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        let colorScheme = style.colorScheme(theme)
        let background = style.background(theme)

        NavigationStack {
            content
                .background(background.ignoresSafeArea())
        }
        .environment(\.colorScheme, colorScheme)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .tint(style.tint(theme))
        .presentationBackground(background)
    }
}

struct TaskSheetHeaderBar<Principal: View>: View {
    let cancellation: TaskSheetAction
    let confirmation: TaskSheetAction
    @ViewBuilder let principal: Principal

    @Environment(ThemeManager.self) private var theme

    init(
        cancellation: TaskSheetAction,
        confirmation: TaskSheetAction,
        @ViewBuilder principal: () -> Principal
    ) {
        self.cancellation = cancellation
        self.confirmation = confirmation
        self.principal = principal()
    }

    var body: some View {
        HStack(spacing: TaskSheetHeaderMetrics.itemSpacing) {
            taskSheetButton(cancellation)
                .foregroundStyle(theme.primaryText)
                .frame(
                    width: TaskSheetHeaderMetrics.actionSlotWidth,
                    alignment: .leading
                )

            HStack(spacing: TaskSheetHeaderMetrics.itemSpacing) {
                principal
            }
            .frame(maxWidth: .infinity)

            taskSheetButton(confirmation)
                .foregroundStyle(theme.accent)
                .frame(
                    width: TaskSheetHeaderMetrics.actionSlotWidth,
                    alignment: .trailing
                )
        }
        .font(AppTypography.body)
        .padding(.horizontal, TaskSheetHeaderMetrics.horizontalPadding)
        .padding(.vertical, TaskSheetHeaderMetrics.verticalPadding)
        .frame(maxWidth: .infinity, minHeight: TaskSheetHeaderMetrics.minHeight)
        .background(theme.sheetBackground)
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

enum TaskSheetHeaderMetrics {
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 10
    static let minHeight: CGFloat = 56
    static let actionSlotWidth: CGFloat = 64
    static let itemSpacing: CGFloat = 8
}

struct TaskSheetAction {
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

extension View {
    func taskSheetChrome(
        title: LocalizedStringKey? = nil,
        titleDisplayMode: NavigationBarItem.TitleDisplayMode = .inline,
        cancellation: TaskSheetAction? = nil,
        confirmation: TaskSheetAction? = nil
    ) -> some View {
        modifier(
            TaskSheetChromeModifier(
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

    func taskSheetChrome<Principal: View>(
        title: LocalizedStringKey? = nil,
        titleDisplayMode: NavigationBarItem.TitleDisplayMode = .inline,
        cancellation: TaskSheetAction? = nil,
        confirmation: TaskSheetAction? = nil,
        @ViewBuilder principal: @escaping () -> Principal
    ) -> some View {
        modifier(
            TaskSheetChromeModifier(
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

private struct TaskSheetChromeModifier<Principal: View>: ViewModifier {
    let title: LocalizedStringKey?
    let titleDisplayMode: NavigationBarItem.TitleDisplayMode
    let cancellation: TaskSheetAction?
    let confirmation: TaskSheetAction?
    let showsPrincipal: Bool
    @ViewBuilder let principal: () -> Principal

    func body(content: Content) -> some View {
        content
            .modifier(TaskSheetTitleModifier(title: title, titleDisplayMode: titleDisplayMode))
            .toolbar {
                if let cancellation {
                    ToolbarItem(placement: .cancellationAction) {
                        taskSheetButton(cancellation)
                    }
                }

                if showsPrincipal {
                    ToolbarItem(placement: .principal) {
                        principal()
                    }
                }

                if let confirmation {
                    ToolbarItem(placement: .confirmationAction) {
                        taskSheetButton(confirmation)
                    }
                }
            }
    }

    @ViewBuilder
    private func taskSheetButton(_ action: TaskSheetAction) -> some View {
        let button = Button(role: action.role, action: action.handler) {
            Text(action.title)
        }
        .fontWeight(action.isProminent ? .semibold : .regular)
        .disabled(action.isDisabled)

        if let accessibilityIdentifier = action.accessibilityIdentifier {
            button.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            button
        }
    }
}

private struct TaskSheetTitleModifier: ViewModifier {
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
