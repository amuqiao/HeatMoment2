import Foundation
import Observation

/// 集中式导航路由（见 `docs/design/08-architecture.md` §3）：全局导航意图（根级任务卡片栈、
/// push 栈、覆盖层、应用锁）集中到一个可观察路由 model，通过 `@Environment` 注入全树。
///
/// 页面局部数据状态（如首页的热力图定位 `heatmapFocusDate` / 筛选 `activeFilter`）**不进 Router**，
/// 由对应 feature 的 view model 持有（见 08 §4）。
///
/// **就近浮窗（标签/心情筛选、日期/时间选择）不进 Router**：它们是锚定触发元素的局部同层浮层
/// （popover 语义，背景不下沉、不缩小、不入层级栈，依公理 4），由触发处自身持有的局部锚定状态
/// 就近驱动，不是「跨页级」导航意图，因此不纳入集中路由。
@MainActor
@Observable
final class AppRouter {
    /// 首页 push 栈（`NavigationStack` root 的 path）——预留给真正的 push 型路由。
    var homePath: [HomeRoute] = []

    /// 根级模态第一层（任务卡片栈，由首页发起），用 `item` 驱动 `.sheet(item:)`。
    /// 预览是「弹出阅读卡片」而非 push，故归入任务卡片栈（`rootSheet`），不进 `homePath`。
    var rootSheet: RootSheet?

    /// 年度热力图覆盖层（`ZStack` overlay，非模态）。
    var isHeatmapPresented = false

    /// 应用级/无层叠语义的沉浸全屏（图片查看器等）。
    var fullScreenCover: FullCover?

    /// 隐私锁遮罩，`scenePhase` 驱动。
    var isLocked = false

    init() {}
}

/// 预留：真正的 push 型路由（当前阶段无成员）。
enum HomeRoute: Hashable {}

/// 根级任务卡片栈成员。筛选是就近浮窗，不在此列。
enum RootSheet: Identifiable {
    case preview(UUID)
    case editor(EditorMode)
    case settings
    case paywall(PaywallTrigger)

    var id: String {
        switch self {
        case let .preview(id): "preview-\(id)"
        case let .editor(mode): "editor-\(mode.id)"
        case .settings: "settings"
        case let .paywall(trigger): "paywall-\(trigger)"
        }
    }
}

/// 编辑器的两种打开方式：新建 / 编辑既有时刻。
enum EditorMode: Hashable {
    case create
    case edit(UUID)

    var id: String {
        switch self {
        case .create: "create"
        case let .edit(id): "edit-\(id)"
        }
    }
}

/// Paywall 的触发来源，三类触发 UI 完全一致，只是关闭后回退目标不同（见 08 §6、11-monetization.md）。
enum PaywallTrigger: Hashable {
    case banner
    case quotaMoment
    case quotaPhoto
    case quotaTag
    case restore
}

/// 无层叠语义的沉浸全屏覆盖层。
enum FullCover: Identifiable {
    case imageViewer(momentID: UUID, index: Int)

    var id: String {
        switch self {
        case let .imageViewer(momentID, index): "imageViewer-\(momentID)-\(index)"
        }
    }
}
