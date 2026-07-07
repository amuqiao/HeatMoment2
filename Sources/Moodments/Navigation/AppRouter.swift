import Foundation
import Observation

/// 集中式导航路由（见 `docs/design/08-architecture.md` §3）：全局导航意图（根级任务卡片栈、
/// push 栈、应用锁）集中到一个可观察路由 model，通过 `@Environment` 注入全树。
///
/// 页面局部状态（如首页的热力图展开、定位 `heatmapFocusDate` / 筛选 `activeFilter`）**不进 Router**，
/// 由对应 feature view / view model 持有（见 08 §3/§4）。
///
/// **首页顶部上下文区 / 就地选择层不进 Router**：年度热力图、首页筛选 half-sheet、
/// 编辑字段 popover 都由触发处自身持有局部状态，不是「跨页级」导航意图。
@MainActor
@Observable
final class AppRouter {
    /// 首页 push 栈（`NavigationStack` root 的 path）——预留给真正的 push 型路由。
    var homePath: [HomeRoute] = []

    /// 根级模态第一层（任务卡片栈，由首页发起），用 `item` 驱动 `.sheet(item:)`。
    /// 预览是「弹出阅读卡片」而非 push，故归入任务卡片栈（`rootSheet`），不进 `homePath`。
    var rootSheet: RootSheet?

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
///
/// **预留路由能力**：当前图片查看器由 `MomentPreviewView` 局部 `.fullScreenCover` 就近呈现
/// （sheet 之上无法从根 present，见阶段 4 计划决策 B），故本 Router 路径暂无写入方；
/// 保留给后续「编辑器缩略图 → 查看器」等从非 sheet 场景发起的入口复用。
enum FullCover: Identifiable {
    case imageViewer(momentID: UUID, index: Int)

    var id: String {
        switch self {
        case let .imageViewer(momentID, index): "imageViewer-\(momentID)-\(index)"
        }
    }
}
