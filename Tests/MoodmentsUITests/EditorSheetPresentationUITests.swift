import XCTest

/// 导航骨架验收（见 08-architecture.md §2.2）：点击悬浮新建按钮以任务卡片栈（`.sheet`）打开
/// 真实编辑器（阶段3），断言情绪行/取消/保存等真实控件存在（旧阶段2占位文案「编辑器 · 阶段3」
/// 已随真实内容落地失效）。
final class EditorSheetPresentationUITests: XCTestCase {
    func testTapFABPresentsEditorWithMoodRowAndSaveButton() {
        let app = XCUIApplication()
        // 隔离内存容器，呈现机制验收不受磁盘数据影响。
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        let fab = app.buttons["新建时刻"]
        XCTAssertTrue(fab.waitForExistence(timeout: 10))
        fab.tap()

        XCTAssertTrue(app.buttons["editorMoodRow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editorTagRow"].exists)
        XCTAssertTrue(app.buttons["editorCancelButton"].exists)
        XCTAssertTrue(app.buttons["editorSaveButton"].exists)
    }

    func testEditorCancelShowsDiscardConfirmationAfterDirtyEdit() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        let fab = app.buttons["新建时刻"]
        XCTAssertTrue(fab.waitForExistence(timeout: 10))
        fab.tap()

        let titleField = app.textFields["editorTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("临时记录")

        let cancelButton = app.buttons["editorCancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        cancelButton.tap()

        XCTAssertTrue(app.alerts["放弃编辑？"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["继续编辑"].exists)
        XCTAssertTrue(app.buttons["放弃编辑"].exists)
    }

    func testSettingsRootHasNoExplicitCloseAndChildPageKeepsBackButton() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()

        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["关闭"].exists, "设置根页应依赖系统 sheet 下滑关闭，不显示关闭按钮")

        let tagManageRow = app.buttons["settingsTagManageRow"]
        XCTAssertTrue(tagManageRow.waitForExistence(timeout: 5))
        tagManageRow.tap()

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "设置内子页仍应保留系统返回按钮")
        backButton.tap()

        dismissSettingsSheet(
            app,
            from: app.navigationBars["设置"],
            expectedHomeButtonLabel: "新建时刻"
        )
    }

    func testSettingsTaskSurfacesShareHorizontalBounds() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()

        let proBanner = app.buttons["settingsProBanner"]
        let primarySection = app.otherElements["settingsPrimarySection"]
        let supportSection = app.otherElements["settingsSupportSection"]
        let aboutSection = app.otherElements["settingsAboutSection"]
        XCTAssertTrue(proBanner.waitForExistence(timeout: 5))
        XCTAssertTrue(primarySection.waitForExistence(timeout: 5))
        XCTAssertTrue(supportSection.waitForExistence(timeout: 5))
        XCTAssertTrue(aboutSection.waitForExistence(timeout: 5))

        assertHorizontallyAligned(primarySection, with: proBanner, message: "Pro 横幅应和主设置组同宽")
        assertHorizontallyAligned(supportSection, with: primarySection, message: "设置分组之间应同宽")
        assertHorizontallyAligned(aboutSection, with: primarySection, message: "关于分组应和主设置组同宽")
    }

    func testSettingsPrimaryDetailPagesUseUnifiedNavigationTitles() {
        let app = XCUIApplication()
        openSettings(app)

        assertSettingsDetailTitle(app, rowID: "settingsMoodStatsRow", title: "心情统计")
        assertSettingsDetailTitle(app, rowID: "settingsTagManageRow", title: "标签管理")
        assertSettingsDetailTitle(app, rowID: "settingsTrashRow", title: "垃圾箱")
    }

    func testSettingsSupportDetailPagesUseUnifiedNavigationTitles() {
        let app = XCUIApplication()
        openSettings(app)

        assertSettingsDetailTitle(app, rowID: "settingsLanguageRow", title: "语言")
        assertSettingsDetailTitle(app, rowID: "settingsAppearanceRow", title: "外观主题")
        assertSettingsDetailTitle(app, rowID: "settingsAboutRow", title: "关于心绪日记")
    }

    func testEditorTaskSurfacesShareHorizontalBounds() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        let fab = app.buttons["新建时刻"]
        XCTAssertTrue(fab.waitForExistence(timeout: 10))
        fab.tap()

        let textPanel = app.otherElements["editorTextPanel"]
        let addPhotoButton = app.buttons["editorAddPhotoButton"]
        XCTAssertTrue(textPanel.waitForExistence(timeout: 5))
        XCTAssertTrue(addPhotoButton.waitForExistence(timeout: 5))

        assertHorizontallyAligned(addPhotoButton, with: textPanel, message: "添加照片按钮应和编辑输入面板同宽")
    }

    private func assertHorizontallyAligned(
        _ lhs: XCUIElement,
        with rhs: XCUIElement,
        tolerance: CGFloat = 1.5,
        message: String
    ) {
        XCTAssertEqual(lhs.frame.minX, rhs.frame.minX, accuracy: tolerance, message)
        XCTAssertEqual(lhs.frame.maxX, rhs.frame.maxX, accuracy: tolerance, message)
    }

    private func openSettings(_ app: XCUIApplication) {
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
    }

    private func assertSettingsDetailTitle(_ app: XCUIApplication, rowID: String, title: String) {
        let row = app.buttons[rowID]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "\(rowID) 应存在")
        if !row.isHittable {
            app.swipeUp()
            XCTAssertTrue(row.waitForExistence(timeout: 5), "\(rowID) 应滚动后存在")
        }
        row.tap()
        let navigationBar = app.navigationBars[title]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5), "\(title) 应显示系统导航标题")

        let backButton = navigationBar.buttons["设置"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "\(title) 应保留系统返回按钮")
        backButton.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5), "返回后应回到设置根页")
    }
}
