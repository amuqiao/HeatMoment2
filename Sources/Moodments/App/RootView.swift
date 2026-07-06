import SwiftData
import SwiftUI

/// 根视图：装载时间轴首页，并把 `AppRouter` 的跨页导航意图呈现为对应浮层——
/// 任务卡片栈用 `.sheet(item:)`（page sheet，多层叠加的下沉由系统负责，见 14 ADR-003）、
/// 沉浸全屏用 `.fullScreenCover(item:)`、年度热力图用 `ZStack` 覆盖层（08-architecture.md §2）。
/// 就近浮窗（筛选/日期/时间）不在此处——由触发处局部状态就近驱动、不进 Router。
///
/// **`TimelineModel` 上提**（阶段5必要重构，见该类型头部注释）：在此创建并通过 `.environment()`
/// 注入整棵树（含 `TimelineHomeView` 与热力图覆盖层 `YearHeatmapView`），使时间轴与热力图
/// 共享同一份「定位/筛选」状态，而不是两份互不相干的拷贝。
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(ErrorPresenter.self) private var errorPresenter
    @State private var timelineModel = TimelineModel()

    var body: some View {
        @Bindable var router = router
        TimelineHomeView()
            .sheet(item: $router.rootSheet) { sheet in
                switch sheet {
                case let .preview(id): MomentPreviewView(momentID: id)
                case let .editor(mode):
                    MomentEditorView(mode: mode, modelContainer: modelContext.container)
                case .settings: SettingsSheetView()
                case let .paywall(trigger): ProPaywallView(trigger: trigger)
                }
            }
            // 预留路由入口（见 AppRouter.FullCover 说明）：当前无写入方，图片查看器由预览局部呈现。
            .fullScreenCover(item: $router.fullScreenCover) { cover in
                switch cover {
                case let .imageViewer(momentID, index):
                    ImageViewerView(momentID: momentID, startIndex: index)
                }
            }
            // 顶部锚定非模态展开（依公理4「覆盖层≠任务卡片」）：`alignment: .top` 只让 overlay
            // 占据其内容自身尺寸（一张顶部卡片），不铺满全屏、不用全屏黑遮罩；`.move(edge: .top)
            // + opacity` 转场配合卡片自身继承的 `theme.canvasBackground`，背景时间轴保持可见、不下沉。
            .overlay(alignment: .top) {
                if router.isHeatmapPresented {
                    YearHeatmapView(modelContainer: modelContext.container)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: router.isHeatmapPresented)
            .environment(timelineModel)
            .userFacingErrorAlert(errorPresenter)
            .task {
                // 首启默认标签预置（见 07-data-persistence.md §4）：无条件运行（生产与 UI 测试
                // 均需要），只在 `Tag` 表为空时插入，不依赖任何 `-uiTest*` 启动参数。经后台
                // TagRepository 写入（08 §5 分层契约）。
                do {
                    let tagRepository = TagRepository(modelContainer: modelContext.container)
                    try await DefaultTagSeeder.seedIfNeeded(using: tagRepository)
                } catch {
                    await errorPresenter.report(message: "初始化默认标签失败，请重启应用重试。", underlying: error)
                }
                #if DEBUG
                UITestSupport.seedIfRequested(modelContext)
                UITestSupport.seedMomentQuotaIfRequested(modelContext)
                #endif
            }
    }
}
