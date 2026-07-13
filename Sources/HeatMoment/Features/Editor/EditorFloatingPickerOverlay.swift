import SwiftUI

enum EditorFloatingPicker: Hashable {
    case mood
    case tag
}

struct EditorFloatingPickerAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [EditorFloatingPicker: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [EditorFloatingPicker: Anchor<CGRect>],
        nextValue: () -> [EditorFloatingPicker: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

enum EditorFloatingPickerMetrics {
    static let width: CGFloat = 240
    static let rowHeight: CGFloat = 44
    static let separatorHeight: CGFloat = 0.5
    static let cornerRadius: CGFloat = 14
    static let verticalGap: CGFloat = 10
    static let viewportMargin: CGFloat = 12

    static func listHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return rowHeight }
        let separators = CGFloat(max(rowCount - 1, 0)) * separatorHeight
        return CGFloat(rowCount) * rowHeight + separators
    }

    static func resolvedHeight(rowCount: Int, maxHeight: CGFloat) -> CGFloat {
        min(listHeight(rowCount: rowCount), max(rowHeight, maxHeight))
    }
}

struct EditorFloatingPickerOverlay: View {
    let activePicker: EditorFloatingPicker
    let anchorFrame: CGRect
    let containerSize: CGSize
    let selectedMood: Mood
    let selectedTagIDs: [UUID]
    let onSelectMood: (Mood) -> Void
    let onToggleTag: (TagSnapshot) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    onDismiss()
                }
                .accessibilityIdentifier("editorFloatingPickerDismissRegion")
                .accessibilityLabel(Text("关闭选择菜单"))

            floatingPickerContent(maxHeight: maxMenuHeight)
                .offset(x: menuLeading, y: menuTop)
        }
    }

    private var menuTop: CGFloat {
        anchorFrame.maxY + EditorFloatingPickerMetrics.verticalGap
    }

    private var maxMenuHeight: CGFloat {
        max(
            EditorFloatingPickerMetrics.rowHeight,
            containerSize.height - menuTop - EditorFloatingPickerMetrics.viewportMargin
        )
    }

    private var menuLeading: CGFloat {
        let preferredLeading =
            switch activePicker {
            case .mood:
                anchorFrame.minX
            case .tag:
                anchorFrame.maxX - EditorFloatingPickerMetrics.width
            }
        let minLeading = EditorFloatingPickerMetrics.viewportMargin
        let maxLeading = max(
            minLeading,
            containerSize.width - EditorFloatingPickerMetrics.width
                - EditorFloatingPickerMetrics.viewportMargin
        )
        return min(max(preferredLeading, minLeading), maxLeading)
    }

    @ViewBuilder
    private func floatingPickerContent(maxHeight: CGFloat) -> some View {
        switch activePicker {
        case .mood:
            MoodPickerView(selectedMood: selectedMood, maxHeight: maxHeight, onSelect: onSelectMood)
        case .tag:
            TagPickerView(
                selectedTagIDs: selectedTagIDs,
                maxHeight: maxHeight,
                onToggle: onToggleTag
            )
        }
    }
}
