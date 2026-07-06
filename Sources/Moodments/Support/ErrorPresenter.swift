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

    private static let logger = Logger(subsystem: "com.moodments.app", category: "ErrorPresenter")

    init() {}

    /// 上报一次可恢复的写失败：写日志（无条件，debug/release 均上报）+ 置 `currentError`
    /// （驱动 `.userFacingErrorAlert`）。
    /// - Parameters:
    ///   - message: 面向用户的中文提示（各调用方按业务场景措辞）。
    ///   - underlying: 原始错误，只进日志、不展示给用户。
    func report(message: String, underlying: Error) {
        Self.logger.error("\(message, privacy: .public)：\(String(describing: underlying), privacy: .public)")
        currentError = UserFacingError(title: "出错了", message: message)
    }

    func dismiss() {
        currentError = nil
    }
}
