import XCTest

/// 免费额度拦截验收（见 `docs/product-mental-model.md` §3.1、
/// `docs/plans/implementation-plan.md` 阶段 3 验收：第 11 篇 / 第 4 标签 / 第 4 张照片）。
final class QuotaBlockUITests: XCTestCase {
    /// 篇数额度：预置 10 篇（占满免费额度）后点新建，应直接弹出 Paywall、编辑器不打开
    /// （见 `TimelineHomeView` 的前置闸门：canonical count + `QuotaService`）。
    func testEleventhMomentBlocked() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedMomentQuota"]
        app.launch()

        let fab = app.buttons["新建时刻"]
        XCTAssertTrue(fab.waitForExistence(timeout: 10))
        fab.tap()

        XCTAssertTrue(app.navigationBars["Pro 会员"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["editorSaveButton"].exists, "超额时编辑器不应被打开")

        let closeButton = app.buttons["paywallCloseButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        closeButton.tap()
        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 5), "关闭 Paywall 后应回到时间轴")
    }

    /// 标签额度：首启已默认预置 3 个标签（工作/生活/健康，占满免费额度，见 `DefaultTagSeeder`
    /// 与阶段 3 计划决策4）。标签新增只归设置页标签管理；点右上「+」应直接触发 Paywall，
    /// 而非打开新建标签卡片。
    func testFourthTagBlocked() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 10))

        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        let tagManageRow = app.buttons["settingsTagManageRow"]
        XCTAssertTrue(tagManageRow.waitForExistence(timeout: 5))
        tagManageRow.tap()

        let addButton = app.buttons["tagManageAddButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(app.navigationBars["Pro 会员"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["tagCreateNameField"].exists, "超额时不应打开新建标签卡片")
    }

    /// 照片额度：借助 DEBUG-only 调试注入入口（见 `EditorPhotoSection`/`UITestSupport`，
    /// 系统 `PhotosPicker` 无法被 `XCUITest` 可靠驱动，见阶段 3 计划决策1）注入 3 张占满免费额度，
    /// 再点**真实「追加照片」按钮**走前置闸门（不经系统 PhotosPicker），应触发 Paywall——
    /// 覆盖 `EditorPhotoSection.requestAddPhotos → QuotaService` 这条真实用户路径的照片额度判定。
    func testFourthPhotoBlocked() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestPhotoInjection"]
        app.launch()

        let fab = app.buttons["新建时刻"]
        XCTAssertTrue(fab.waitForExistence(timeout: 10))
        fab.tap()

        let injectButton = app.buttons["editorInjectPhotoButton"]
        XCTAssertTrue(injectButton.waitForExistence(timeout: 5))
        injectButton.tap()  // 注入 3 张，占满免费额度（freePhotosPerMomentLimit == 3）
        injectButton.tap()
        injectButton.tap()

        let appendButton = app.buttons["editorAppendPhotoButton"]
        XCTAssertTrue(appendButton.waitForExistence(timeout: 5))
        appendButton.tap()  // 已满额，前置闸门应直接弹 Paywall、不打开系统选择器

        XCTAssertTrue(app.navigationBars["Pro 会员"].waitForExistence(timeout: 5))
    }
}
