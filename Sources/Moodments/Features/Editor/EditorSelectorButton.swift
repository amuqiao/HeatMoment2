import SwiftUI

struct EditorSelectorButton<Leading: View, Summary: View>: View {
    @Environment(ThemeManager.self) private var theme

    let layout: MomentEditorLayoutMetrics
    @ViewBuilder private let leading: Leading
    @ViewBuilder private let summary: Summary

    init(
        layout: MomentEditorLayoutMetrics,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder summary: () -> Summary
    ) {
        self.layout = layout
        self.leading = leading()
        self.summary = summary()
    }

    var body: some View {
        HStack(spacing: layout.selectorContentSpacing) {
            leading
                .frame(width: layout.selectorIconWidth, alignment: .leading)
            GeometryReader { proxy in
                summary
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                    .clipped()
            }
            .frame(maxWidth: .infinity, minHeight: layout.selectorMinHeight)
            Image(systemName: "chevron.down")
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
                .frame(width: layout.selectorChevronWidth, alignment: .trailing)
        }
        .padding(.horizontal, layout.selectorHorizontalPadding)
        .frame(maxWidth: .infinity, minHeight: layout.selectorMinHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: layout.selectorCornerRadius, style: .continuous)
                .fill(theme.sheetPanelBackground)
        )
        .contentShape(Rectangle())
    }
}

struct EditorTagSelectionSummary: View {
    let selectedNames: [String]
    let layout: MomentEditorLayoutMetrics

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
        HStack(spacing: layout.tagChipSpacing) {
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
            .padding(.horizontal, layout.tagChipHorizontalPadding)
            .padding(.vertical, layout.tagChipVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: layout.tagChipCornerRadius, style: .continuous)
                    .fill(theme.selectionFill)
            )
    }
}
