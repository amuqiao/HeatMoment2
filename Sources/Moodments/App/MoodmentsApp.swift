import SwiftUI

/// App 入口。阶段 0 只装载占位根视图；阶段 1 起接入 ModelContainer / AppRouter / ThemeManager。
@main
struct MoodmentsApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
