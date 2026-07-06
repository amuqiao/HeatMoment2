import Foundation
import Observation
import os

/// 面向用户的一次错误呈现内容（标题 + 消息），`Identifiable` 供 `.alert` 驱动。
struct UserFacingError: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

/// 统一错误通道（见 `docs/plans/implementation-plan.md` 阶段6 决策3、CLAUDE.md「不擅自添加
/// 兜底策略」）：**可恢复的写失败**（编辑器保存/载入/照片、垃圾箱恢复/彻底删除、时间轴删除/
/// 额度前置、标签新建/重命名）统一改走本类型，而不是让进程 `assertionFailure` 中止：
///
/// - **用户可见**：失败驱动 `currentError`，配合 `.userFacingErrorAlert(_:)` 呈现系统 `.alert`；
/// - **debug/release 均上报**：无条件写 `Logger`，不因构建配置差异而在 release 静默；
/// - **不伪造成功、不降级**：本类型只负责「展示」，绝不吞掉错误、绝不把失败当成功处理——
///   调用方各自保证状态真实性（如编辑器保存失败不 `dismiss`、垃圾箱操作失败从仓库 `reload`）。
///
/// 与本类型职责边界：**真正的不变量违反**（如程序内部逻辑保证被打破）仍应 `assertionFailure`
/// 暴露，不归本类型处理——本类型只处理「外部世界可能失败、但程序状态仍然自洽」的可恢复场景。
/// 外观（`AppearanceThemeView`）保存失败是例外：05 §5.3.7 明确要求页内非模态提示、不回滚
/// 视觉，不走本类型（见 `ThemeManager.appearanceSaveFailed`/`photoDisplaySaveFailed`）。
@MainActor
@Observable
final class ErrorPresenter {
    private(set) var currentError: UserFacingError?

    /// 呈现宿主栈（LIFO，见 `UserFacingErrorAlertModifier`）：任务卡片栈/就近浮窗可以**嵌套**在
    /// 另一个已挂 `.userFacingErrorAlert` 的呈现上下文之内且**同时挂载**（如
    /// `RootView` 呈现 `SettingsSheetView`、`SettingsSheetView` push 出的 `TagManageView` 再呈现
    /// `TagCreateSheetView`——三层同时在场，而非互斥的兄弟关系）。若祖先与被其遮挡的后代同时
    /// 绑定同一个 `currentError != nil` 各自呈现系统 `.alert`，会让 UIKit 对「该由谁呈现」产生
    /// 冲突，真机/模拟器实测复现为**整条呈现链被强制折叠回根**（阶段6 review 修复3）——而非文档
    /// 早先设想的「父级 alert 静默不弹、无副作用」。用「最后挂载 = 当前最上层」的栈语义：只让
    /// 当前最上层的宿主真正呈现，其余仍挂载但被遮挡的祖先宿主保持沉默，直至重新成为最上层。
    private var hostStack: [UUID] = []

    private static let logger = Logger(subsystem: "com.moodments.app", category: "ErrorPresenter")

    init() {}

    /// 上报一次可恢复的写失败：写日志（无条件，debug/release 均上报）+ 置 `currentError`
    /// （驱动 `.userFacingErrorAlert`）。
    /// - Parameters:
    ///   - message: 面向用户的中文提示（各调用方按业务场景措辞）。
    ///   - underlying: 原始错误，只进日志、不展示给用户。
    func report(message: String, underlying: Error) {
        // 隐私优先：固定中文 message 是本 App 自身文案、不含用户数据，保持 `.public` 可检索；
        // `underlying` 可能带文件路径/SwiftData 描述等隐含用户数据，改 `.private`，避免明文
        // 泄进系统日志（Console/sysdiagnose 均可见 `.public` 内容）。
        Self.logger.error("\(message, privacy: .public)：\(String(describing: underlying), privacy: .private)")
        currentError = UserFacingError(title: "出错了", message: message)
    }

    func dismiss() {
        currentError = nil
    }

    /// 供 `UserFacingErrorAlertModifier` 在 `.onAppear` 登记本次挂载，入栈成为当前最上层宿主。
    func registerAlertHost() -> UUID {
        let id = UUID()
        hostStack.append(id)
        return id
    }

    /// 供 `UserFacingErrorAlertModifier` 在 `.onDisappear` 注销，退出呈现宿主栈。
    func unregisterAlertHost(_ id: UUID) {
        hostStack.removeAll { $0 == id }
    }

    /// 该宿主当前是否为最上层（栈顶）——只有最上层宿主的 `.alert` 才真正呈现。
    func isTopmostAlertHost(_ id: UUID) -> Bool {
        hostStack.last == id
    }
}
