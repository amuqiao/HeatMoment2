import SwiftUI
import UIKit

enum TaskSurfaceMetrics {
    static let pageHorizontalInset: CGFloat = 16
    static let pageVerticalInset: CGFloat = 20
    static let pageBottomInset: CGFloat = 56
    static let contentMaxWidth: CGFloat = 560
    static let groupSpacing: CGFloat = 24
    static let sectionTitleSpacing: CGFloat = 10
    static let panelPadding: CGFloat = 16
    static let panelCornerRadius: CGFloat = 16
    static let rowMinHeight: CGFloat = 56
    static let rowHorizontalPadding: CGFloat = 16
    static let listRowVerticalInset: CGFloat = 6
}

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

struct TaskPageScrollView<Content: View>: View {
    @Environment(ThemeManager.self) private var theme

    private let spacing: CGFloat
    private let accessibilityIdentifier: String?
    @ViewBuilder private let content: Content

    init(
        spacing: CGFloat = TaskSurfaceMetrics.groupSpacing,
        accessibilityIdentifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        let scrollView = ScrollView {
            TaskResponsiveContent(spacing: spacing) {
                content
            }
        }
        .background(theme.sheetBackground.ignoresSafeArea())

        if let accessibilityIdentifier {
            scrollView.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            scrollView
        }
    }
}

struct TaskResponsiveContent<Content: View>: View {
    private let spacing: CGFloat
    @ViewBuilder private let content: Content

    init(spacing: CGFloat = TaskSurfaceMetrics.groupSpacing, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(.horizontal, TaskSurfaceMetrics.pageHorizontalInset)
        .padding(.top, TaskSurfaceMetrics.pageVerticalInset)
        .padding(.bottom, TaskSurfaceMetrics.pageBottomInset)
        .taskResponsiveFrame()
    }
}

struct TaskSurfaceSection<Content: View>: View {
    @Environment(ThemeManager.self) private var theme

    private let title: String?
    private let accessibilityIdentifier: String?
    @ViewBuilder private let content: Content

    init(
        title: String? = nil,
        accessibilityIdentifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TaskSurfaceMetrics.sectionTitleSpacing) {
            if let title {
                Text(title)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(theme.primaryText)
                    .padding(.horizontal, 2)
            }

            TaskSurfacePanel {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .taskSurfaceMeasurementIdentifier(accessibilityIdentifier)
    }
}

struct TaskSurfacePanel<Content: View>: View {
    @Environment(ThemeManager.self) private var theme

    private let padding: EdgeInsets
    @ViewBuilder private let content: Content

    init(
        padding: EdgeInsets = EdgeInsets(
            top: TaskSurfaceMetrics.panelPadding,
            leading: TaskSurfaceMetrics.panelPadding,
            bottom: TaskSurfaceMetrics.panelPadding,
            trailing: TaskSurfaceMetrics.panelPadding
        ),
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TaskSurfaceMetrics.panelCornerRadius, style: .continuous)
                .fill(theme.sheetPanelBackground)
        )
    }
}

struct TaskSurfaceRow<Leading: View, Trailing: View>: View {
    @Environment(ThemeManager.self) private var theme

    @ViewBuilder private let leading: Leading
    @ViewBuilder private let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    init(@ViewBuilder leading: () -> Leading) where Trailing == EmptyView {
        self.leading = leading()
        self.trailing = EmptyView()
    }

    var body: some View {
        HStack(spacing: 12) {
            leading
            Spacer(minLength: 12)
            trailing
        }
        .font(AppTypography.body)
        .foregroundStyle(theme.primaryText)
        .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
        .frame(maxWidth: .infinity, minHeight: TaskSurfaceMetrics.rowMinHeight, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct TaskDisclosureIndicator: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.body.weight(.semibold))
            .foregroundStyle(theme.secondaryText)
    }
}

struct TaskSurfaceSeparator: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.separator)
            .frame(height: 1 / UIScreen.main.scale)
            .padding(.leading, TaskSurfaceMetrics.rowHorizontalPadding)
    }
}

extension View {
    func taskResponsiveFrame() -> some View {
        frame(maxWidth: TaskSurfaceMetrics.contentMaxWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
    }

    func taskListContentFrame() -> some View {
        frame(maxWidth: TaskSurfaceMetrics.contentMaxWidth)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    func taskSurfaceMeasurementIdentifier(_ identifier: String?) -> some View {
        #if DEBUG
            let shouldExposeIdentifier = UITestSupport.wantsTaskSurfaceMeasurementIdentifiers
        #else
            let shouldExposeIdentifier = false
        #endif

        if let identifier, shouldExposeIdentifier {
            overlay {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Color.clear
                        .frame(height: 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityIdentifier(identifier)
                        .allowsHitTesting(false)
                }
            }
        } else {
            self
        }
    }
}
