import SwiftUI

/// 隐私锁（见 `docs/design/10-security-privacy.md` §10.1、08-architecture.md §2.2）：应用级
/// `.fullScreenCover`，挂载于比 `AppRouter.rootSheet`/覆盖层更外层的位置（见
/// `MoodmentsApp.body`），验证通过前不渲染任何 Moment 内容、无手势关闭。出现即自动发起一次
/// 验证（`.task`），失败/取消展示重试按钮，不吞错（见 `BiometricLockService`）。
struct PrivacyLockView: View {
    /// 验证成功时调用（调用方负责把 `AppRouter.isLocked` 置回 `false`，本视图不直接持有
    /// 路由引用）。
    let onUnlock: () -> Void

    @Environment(ThemeManager.self) private var theme
    @State private var isVerifying = false
    @State private var lastAttemptFailed = false

    private let service = BiometricLockService()

    var body: some View {
        ZStack {
            theme.canvasBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "faceid")
                    .font(.system(size: 56))
                    .foregroundStyle(theme.accent)
                Text("「时刻」已锁定")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(theme.primaryText)

                if lastAttemptFailed {
                    Text("验证未通过，请重试")
                        .font(AppTypography.caption)
                        .foregroundStyle(theme.danger)
                        .accessibilityIdentifier("privacyLockFailedHint")
                }

                Button {
                    Task { await verify() }
                } label: {
                    if isVerifying {
                        ProgressView().tint(.white)
                    } else {
                        Text(lastAttemptFailed ? "重新验证" : "解锁")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
                .disabled(isVerifying)
                .accessibilityIdentifier("privacyLockUnlockButton")
            }
            .padding(32)
        }
        // 验证通过前不渲染任何 Moment 内容（本视图整体即是「验证通过前」的呈现，`RootView`
        // 内容被本视图从最外层完全遮盖，见 `MoodmentsApp.body` 的挂载位置）。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("privacyLockView")
        // 防止 VoiceOver 焦点穿透到底层敏感内容（10 §10.1.5）。
        .accessibilityAddTraits(.isModal)
        .task {
            await verify()
        }
    }

    private func verify() async {
        guard !isVerifying else { return }
        isVerifying = true
        defer { isVerifying = false }
        do {
            let success = try await service.evaluate(reason: "验证以解锁「时刻」")
            lastAttemptFailed = !success
            if success {
                onUnlock()
            }
        } catch {
            // 不吞错：验证过程异常（用户取消、系统繁忙等 `LAError`）允许用户手动重试，不属于
            // App 级不可恢复错误（10 §10.1.1）；异常本身已由系统级交互呈现给用户，此处只切换
            // 到「可重试」态，不重复弹出面向用户的错误提示。
            lastAttemptFailed = true
        }
    }
}

#Preview {
    PrivacyLockView(onUnlock: {})
        .environment(ThemeManager())
}
