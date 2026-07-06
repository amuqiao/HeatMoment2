import XCTest

/// 隐私锁生命周期冒烟（见 `docs/design/10-security-privacy.md` §10.1、阶段7计划决策6）：
/// 真实 Face ID/密码系统交互无法被 `XCUITest` 驱动（同 `PhotosPicker` 限制），借助 DEBUG-only
/// 注入 hook（`-uiTestForcePrivacyLockEnabled` 强制开启隐私锁 + `-uiTestBiometricAlwaysSucceed`/
/// `-uiTestBiometricAlwaysFail` 伪造 `BiometricLockService` 验证结果，见 `UITestSupport`）验证
/// 冷启动锁定 / 验证通过后放行 / 回前台重新锁定 / 验证失败前内容不可见的生命周期时序。
///
/// **断言约定**：`PrivacyLockView` 带 `.accessibilityAddTraits(.isModal)`，`XCUITest` 会把它
/// 归类为 `alerts`（而非 `otherElements`），故以锁内稳定元素（「已锁定」标题文案）判定锁是否
/// 在场；「验证通过前内容不可见」以时间轴 FAB `isHittable == false`（被全屏锁遮挡不可交互）
/// 断言，而非 `exists`——`.isModal` 不会把下层从可访问性树移除，`exists` 仍为真（见 code review）。
final class PrivacyLockUITests: XCTestCase {
    private let lockTitle = "「时刻」已锁定"

    /// 冷启动 + 验证恒失败：隐私锁应持续遮盖，时间轴内容（FAB）不可交互，且展示可重试的失败态
    /// （见 10 §10.1.3「验证通过前不渲染任何 Moment 内容」）。
    func testColdStartKeepsContentHiddenUntilVerified() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestForcePrivacyLockEnabled", "-uiTestBiometricAlwaysFail"]
        app.launch()

        XCTAssertTrue(app.staticTexts[lockTitle].waitForExistence(timeout: 10), "冷启动应锁定")
        XCTAssertTrue(app.staticTexts["privacyLockFailedHint"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["新建时刻"].isHittable, "验证通过前时间轴内容应被锁遮挡、不可交互")

        // 重试按钮应仍可点击（允许用户重试，不因一次失败进入死锁态，见 10 §10.1.1）。
        let retryButton = app.buttons["privacyLockUnlockButton"]
        XCTAssertTrue(retryButton.exists)
        retryButton.tap()
        XCTAssertTrue(app.staticTexts[lockTitle].exists, "伪造的恒失败验证下重试后仍应保持锁定")
        XCTAssertFalse(app.buttons["新建时刻"].isHittable)
    }

    /// 冷启动 + 验证恒成功：隐私锁应自动验证通过并放行，时间轴内容正常出现、锁消失。
    func testColdStartUnlocksAndRevealsContentOnSuccess() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestForcePrivacyLockEnabled", "-uiTestBiometricAlwaysSucceed"]
        app.launch()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 10), "验证通过后应放行、展示时间轴内容")
        XCTAssertTrue(app.buttons["新建时刻"].isHittable, "放行后时间轴内容应可交互")
        XCTAssertFalse(app.staticTexts[lockTitle].exists, "验证通过后锁应消失")
    }

    /// 未开启隐私锁（默认关闭态，见 10 §10.1.2 截图为关闭态）：冷启动不应出现隐私锁遮罩。
    func testLockNotShownWhenPreferenceDisabled() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts[lockTitle].exists)
    }

    /// 回前台重新锁定（「立即锁定」策略，见 10 §10.1.3）：验证恒失败场景下，把 App 切到后台
    /// 再切回前台，隐私锁应重新出现并持续遮盖（不因曾经在冷启动侧已展示过锁屏就跳过后续锁定）。
    func testReturningFromBackgroundLocksAgain() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestForcePrivacyLockEnabled", "-uiTestBiometricAlwaysFail"]
        app.launch()

        XCTAssertTrue(app.staticTexts[lockTitle].waitForExistence(timeout: 10))

        XCUIDevice.shared.press(.home)
        _ = app.wait(for: .runningBackground, timeout: 5)

        app.activate()
        XCTAssertTrue(app.staticTexts[lockTitle].waitForExistence(timeout: 10), "回前台应重新展示隐私锁")
        XCTAssertFalse(app.buttons["新建时刻"].isHittable)
    }
}
