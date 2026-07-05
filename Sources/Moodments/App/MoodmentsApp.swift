import SwiftData
import SwiftUI

/// App 入口：装配 SwiftData `ModelContainer`（本地 config，阶段 7 再切 CloudKit）、集中路由
/// `AppRouter` 与主题 `ThemeManager`，注入 Environment 供全树消费（见 08-architecture.md §0/§3/§4）。
@main
struct MoodmentsApp: App {
    @State private var router = AppRouter()
    @State private var theme = ThemeManager()
    private let container: ModelContainer

    init() {
        do {
            #if DEBUG
            container = UITestSupport.wantsInMemoryContainer
                ? try ModelContainerConfig.makeInMemoryContainer()
                : try ModelContainerConfig.makeLocalContainer()
            #else
            container = try ModelContainerConfig.makeLocalContainer()
            #endif
        } catch {
            // 不做静默兜底：容器无法建立属不可恢复的启动错误，快速暴露（见 CLAUDE.md）。
            fatalError("ModelContainer 初始化失败：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(theme)
                .preferredColorScheme(theme.mode == .dark ? .dark : .light)
        }
        .modelContainer(container)
    }
}
