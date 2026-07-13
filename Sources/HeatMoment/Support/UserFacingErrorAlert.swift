import SwiftUI

extension View {
    /// 统一错误通道的呈现（见 `Support/ErrorPresenter`）：绑定 `presenter.currentError` 驱动
    /// 系统 `.alert`。**`.alert` 不跨 sheet 边界**（每个 page sheet 是独立的呈现上下文），
    /// 故需在各顶层呈现上下文（`RootView` / `MomentEditorView` 根 / `SettingsSheetView` 根）及
    /// 嵌套其中、可能成为最前 sheet/就近浮窗的任务卡片（`TagCreateSheetView`/`TagPickerView`
    /// 等）各挂一份，均绑定同一个经 `@Environment` 注入的共享 `ErrorPresenter` 实例——因为
    /// `.sheet`/`.popover` 内容默认继承呈现它的视图当时的环境值，各处看到的是同一份状态。
    ///
    /// **祖先与被其遮挡的后代会同时挂载**（如 `RootView` 呈现 `SettingsSheetView`、其 push 出的
    /// `TagManageView` 再呈现 `TagCreateSheetView`——三层同时在场，非互斥兄弟关系）：本修饰符
    /// 借 `ErrorPresenter` 的呈现宿主栈只让当前最上层的挂载真正调用 `.alert`，避免多个同时挂载
    /// 的 `.alert` 各自尝试呈现同一个 `currentError` 而让 UIKit 呈现链被强制折叠（阶段6 review
    /// 修复3 实测复现：撞名保存失败后既不见错误提示，又整个设置栈被回弹到时间轴根）。
    func userFacingErrorAlert(_ presenter: ErrorPresenter) -> some View {
        modifier(UserFacingErrorAlertModifier(presenter: presenter))
    }
}

private struct UserFacingErrorAlertModifier: ViewModifier {
    let presenter: ErrorPresenter

    @State private var hostID: UUID?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard hostID == nil else { return }
                hostID = presenter.registerAlertHost()
            }
            .onDisappear {
                guard let hostID else { return }
                presenter.unregisterAlertHost(hostID)
                self.hostID = nil
            }
            .alert(
                presenter.currentError?.title ?? "",
                isPresented: Binding(
                    get: { presenter.currentError != nil && isTopmostHost },
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

    /// 未完成 `.onAppear` 登记前（首帧）保守视为非最上层，避免抢在真正的最上层宿主注册前
    /// 误呈现。
    private var isTopmostHost: Bool {
        guard let hostID else { return false }
        return presenter.isTopmostAlertHost(hostID)
    }
}
