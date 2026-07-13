import SwiftUI

/// 行级危险操作的统一 SwiftUI swipe 展示层。
///
/// 本组件只复用成熟系统 `.swipeActions` 的呈现方式，不承载业务删除语义。
/// 删除、恢复或清理等领域动作仍分别留在调用方处理。
extension View {
    func destructiveSwipeAction(
        title: String,
        systemImage: String = "trash",
        accessibilityIdentifier: String,
        accessibilityActionName: String? = nil,
        allowsFullSwipe: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        modifier(
            DestructiveSwipeActionModifier(
                title: title,
                systemImage: systemImage,
                accessibilityIdentifier: accessibilityIdentifier,
                accessibilityActionName: accessibilityActionName ?? title,
                allowsFullSwipe: allowsFullSwipe,
                action: action
            )
        )
    }
}

private struct DestructiveSwipeActionModifier: ViewModifier {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let accessibilityActionName: String
    let allowsFullSwipe: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: allowsFullSwipe) {
                Button(role: .destructive) {
                    action()
                } label: {
                    Label(title, systemImage: systemImage)
                }
                .accessibilityIdentifier(accessibilityIdentifier)
            }
            .accessibilityAction(named: Text(accessibilityActionName)) { action() }
    }
}
