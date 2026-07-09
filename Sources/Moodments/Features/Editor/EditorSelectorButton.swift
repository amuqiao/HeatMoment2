import SwiftUI

enum EditorLayout {
    static let selectorMinHeight: CGFloat = 46
    static let selectorIconWidth: CGFloat = 28
    static let selectorChevronWidth: CGFloat = 22
    static let selectorCornerRadius: CGFloat = 14
    static let selectorContentSpacing: CGFloat = 8
    static let tagChipCornerRadius: CGFloat = 7
    static let tagChipHorizontalPadding: CGFloat = 8
    static let tagChipVerticalPadding: CGFloat = 3
    static let bodyMinHeight: CGFloat = 170
    static let chromeHorizontalPadding: CGFloat = 16
    static let chromeVerticalPadding: CGFloat = 10
    static let chromeMinHeight: CGFloat = 56
    static let chromeActionSlotWidth: CGFloat = 64
    static let chromeItemSpacing: CGFloat = 8
    static let contentTopInset: CGFloat = 10
    static let contentGroupSpacing: CGFloat = 20

    static var contentInsets: EdgeInsets {
        EdgeInsets(
            top: contentTopInset,
            leading: TaskSurfaceMetrics.pageHorizontalInset,
            bottom: TaskSurfaceMetrics.pageBottomInset,
            trailing: TaskSurfaceMetrics.pageHorizontalInset
        )
    }
}

struct EditorSelectorButton<Leading: View, Summary: View>: View {
    @Environment(ThemeManager.self) private var theme

    @ViewBuilder private let leading: Leading
    @ViewBuilder private let summary: Summary

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder summary: () -> Summary
    ) {
        self.leading = leading()
        self.summary = summary()
    }

    var body: some View {
        HStack(spacing: EditorLayout.selectorContentSpacing) {
            leading
                .frame(width: EditorLayout.selectorIconWidth, alignment: .leading)
            GeometryReader { proxy in
                summary
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                    .clipped()
            }
            .frame(maxWidth: .infinity, minHeight: EditorLayout.selectorMinHeight)
            Image(systemName: "chevron.down")
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: EditorLayout.selectorChevronWidth, alignment: .trailing)
        }
        .padding(.horizontal, TaskSurfaceMetrics.rowHorizontalPadding)
        .frame(maxWidth: .infinity, minHeight: EditorLayout.selectorMinHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: EditorLayout.selectorCornerRadius, style: .continuous)
                .fill(theme.sheetPanelBackground)
        )
        .contentShape(Rectangle())
    }
}

struct EditorTagSelectionSummary: View {
    let selectedNames: [String]

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        if selectedNames.isEmpty {
            Text(LanguagePreference.localizedString("选择标签"))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            ViewThatFits(in: .horizontal) {
                tagChipRow(names: selectedNames, overflowCount: 0)
                if selectedNames.count > 2 {
                    tagChipRow(
                        names: Array(selectedNames.prefix(2)),
                        overflowCount: selectedNames.count - 2
                    )
                }
                if selectedNames.count > 1 {
                    tagChipRow(
                        names: Array(selectedNames.prefix(1)),
                        overflowCount: selectedNames.count - 1
                    )
                }
                Text("\(selectedNames.count) 个标签")
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func tagChipRow(names: [String], overflowCount: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                tagChip(name)
            }
            if overflowCount > 0 {
                tagChip("+\(overflowCount)")
            }
        }
        .lineLimit(1)
    }

    private func tagChip(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(theme.primaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, EditorLayout.tagChipHorizontalPadding)
            .padding(.vertical, EditorLayout.tagChipVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: EditorLayout.tagChipCornerRadius, style: .continuous)
                    .fill(theme.selectionFill)
            )
    }
}
