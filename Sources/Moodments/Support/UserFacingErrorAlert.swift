import SwiftUI

extension View {
    /// 统一错误通道的呈现（见 `Support/ErrorPresenter`）：绑定 `presenter.currentError` 驱动
    /// 系统 `.alert`。**`.alert` 不跨 sheet 边界**（每个 page sheet 是独立的呈现上下文），
    /// 故需在各顶层呈现上下文（`RootView` / `MomentEditorView` 根 / `SettingsSheetView` 根）
    /// 各挂一份，均绑定同一个经 `@Environment` 注入的共享 `ErrorPresenter` 实例——
    /// 因为 `.sheet` 内容默认继承呈现它的视图当时的环境值，三处看到的是同一份状态。
    func userFacingErrorAlert(_ presenter: ErrorPresenter) -> some View {
        modifier(UserFacingErrorAlertModifier(presenter: presenter))
    }
}

private struct UserFacingErrorAlertModifier: ViewModifier {
    let presenter: ErrorPresenter

    func body(content: Content) -> some View {
        content.alert(
            presenter.currentError?.title ?? "",
            isPresented: Binding(
                get: { presenter.currentError != nil },
                set: { isPresented in
                    if !isPresented { presenter.dismiss() }
                }
            )
        ) {
            Button("好的") { presenter.dismiss() }
        } message: {
            Text(presenter.currentError?.message ?? "")
        }
    }
}
