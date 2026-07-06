import SwiftData
import SwiftUI

/// 根视图：装载时间轴首页，并把 `AppRouter` 的跨页导航意图呈现为对应浮层——
/// 任务卡片栈用 `.sheet(item:)`（page sheet，多层叠加的下沉由系统负责，见 14 ADR-003）、
/// 沉浸全屏用 `.fullScreenCover(item:)`、年度热力图用 `ZStack` 覆盖层（08-architecture.md §2）。
/// 就近浮窗（筛选/日期/时间）不在此处——由触发处局部状态就近驱动、不进 Router。
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

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
            .fullScreenCover(item: $router.fullScreenCover) { cover in
                switch cover {
                case .imageViewer:
                    // 图片查看器在阶段 4 实现；此处占位保证 item 穷尽、可关闭。
                    ImageViewerPlaceholder()
                }
            }
            .overlay {
                if router.isHeatmapPresented {
                    YearHeatmapView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: router.isHeatmapPresented)
            .task {
                // 首启默认标签预置（见 07-data-persistence.md §4）：无条件运行（生产与 UI 测试
                // 均需要），只在 `Tag` 表为空时插入，不依赖任何 `-uiTest*` 启动参数。
                do {
                    try DefaultTagSeeder.seedIfNeeded(modelContext)
                } catch {
                    assertionFailure("默认标签预置失败：\(error)")
                }
                #if DEBUG
                UITestSupport.seedIfRequested(modelContext)
                UITestSupport.seedMomentQuotaIfRequested(modelContext)
                #endif
            }
    }
}

/// 阶段 2 占位：图片查看器（`.fullScreenCover`）内容留阶段 4，先保证可关闭、item 穷尽。
private struct ImageViewerPlaceholder: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("图片查看器 · 阶段4")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Button("关闭") { router.fullScreenCover = nil }
                    .foregroundStyle(.white)
            }
        }
    }
}
