import XCTest

/// 外观保存失败的异常反馈验收（见 `docs/current/implementation-truth.md` §5.3.7、
/// `docs/plans/implementation-plan.md` 阶段6 决策3）：`-uiTestFailAppearanceSave` 注入必失败
/// `AppearanceStore` → 切主色/图片显示后界面**已按乐观更新生效、不回滚**，同时页内出现对应的
/// 独立失败提示（主色/模式/纹理 用「外观设置保存失败」；图片显示单独用「照片显示设置保存
/// 失败」）——两类提示均为**页内非模态**元素，不是全局 `.alert`。
final class AppearanceSaveFailureUITests: XCTestCase {
    func testAccentColorSaveFailureShowsInlineNoticeWithoutRollingBackSelection() {
        let app = XCUIApplication.heatMoment()
        app.launchArguments = ["-uiTestFailAppearanceSave"]
        app.launch()

        openAppearanceThemeView(app)

        let redOption = app.buttons["appearanceAccentOption-red"]
        XCTAssertTrue(redOption.waitForExistence(timeout: 5))
        redOption.tap()

        XCTAssertTrue(
            redOption.isSelected,
            "保存失败不应回滚已生效的视觉选择（乐观更新契约，见 docs/current/implementation-truth.md §5.3.7）"
        )
        XCTAssertTrue(
            app.staticTexts["appearanceSaveFailedNotice"].waitForExistence(timeout: 5),
            "主色保存失败应展示「外观设置保存失败」页内提示"
        )
        XCTAssertFalse(
            app.staticTexts["photoDisplaySaveFailedNotice"].exists,
            "主色保存失败不应联动展示照片显示的失败提示（两者分开反馈）"
        )
    }

    func testImageDisplayModeSaveFailureShowsIndependentInlineNotice() {
        let app = XCUIApplication.heatMoment()
        app.launchArguments = ["-uiTestFailAppearanceSave"]
        app.launch()

        openAppearanceThemeView(app)

        // 「图片」分组在页面末尾，需先滚动到底
        // （见 `ThemeSwitchUITests.scrollToBottom` 同类说明）。
        scrollToBottom(app)

        let carouselOption = app.buttons["appearanceImageModeOption-carousel"]
        XCTAssertTrue(carouselOption.waitForExistence(timeout: 5))
        carouselOption.tap()

        // 点选后页面会重新布局、滚动位置不可靠（实测偶发把「图片」分组重新挤出可见范围），
        // 重新滚动到底、重新定位元素后再读取 `isSelected`，不复用点击前的元素句柄/滚动假设。
        scrollToBottom(app)
        let carouselOptionAfterTap = app.buttons["appearanceImageModeOption-carousel"]
        XCTAssertTrue(carouselOptionAfterTap.waitForExistence(timeout: 5))
        XCTAssertTrue(carouselOptionAfterTap.isSelected, "保存失败不应回滚已生效的视觉选择")

        // 失败提示 Section 插在列表**顶部**（`模式` 分组之上），与「图片」分组不在同一屏，
        // 滚回顶部才能定位到它。
        scrollToTop(app)
        XCTAssertTrue(
            app.staticTexts["photoDisplaySaveFailedNotice"].waitForExistence(timeout: 5),
            "图片显示保存失败应展示独立的「照片显示设置保存失败」页内提示"
        )
    }

    // MARK: - Helpers

    private func openAppearanceThemeView(_ app: XCUIApplication) {
        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()

        let appearanceRow = app.buttons["settingsAppearanceRow"]
        XCTAssertTrue(appearanceRow.waitForExistence(timeout: 5))
        appearanceRow.tap()
    }

    /// 在 `AppearanceThemeView` 内反复下滑到底，使末尾分组（「图片」）进入可见区域；
    /// 次数留足余量（5 次）以覆盖点选后重新布局导致的滚动位置漂移。
    private func scrollToBottom(_ app: XCUIApplication) {
        for _ in 0..<5 { app.swipeUp() }
    }

    /// 反复上滑回到列表顶部，定位仅在顶部可见的失败提示 Section。
    private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<5 { app.swipeDown() }
    }
}
