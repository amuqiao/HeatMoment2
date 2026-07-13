import SwiftUI

/// 多任务切换器（App Switcher）快照与录屏防护（见 `docs/current/implementation-truth.md` §10.1.3）：
/// `scenePhase != .active` 时用品牌 Logo/纯色遮罩覆盖真实内容再进入后台快照，防止敏感内容
/// （心情日记标题/正文/照片）出现在多任务预览中。仅在隐私锁功能开启时挂载（见
/// `HeatMomentApp.body`），未开启该功能的用户不承受额外遮罩闪烁。
struct PrivacyMaskView: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        ZStack {
            theme.canvasBackground.ignoresSafeArea()
            Text("心绪日记")
                .font(AppTypography.cardTitle)
                .foregroundStyle(theme.primaryText)
        }
        .accessibilityIdentifier("privacyMaskView")
    }
}

#Preview {
    PrivacyMaskView()
        .environment(ThemeManager())
}
