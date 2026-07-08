import XCTest

/// 导航骨架验收（见 08-architecture.md §2.2）：点击悬浮新建按钮以任务卡片栈（`.sheet`）打开
/// 真实编辑器（阶段3），断言情绪行/取消/保存等真实控件存在（旧阶段2占位文案「编辑器 · 阶段3」
/// 已随真实内容落地失效）。
final class EditorSheetPresentationUITests: XCTestCase {
    func testTapFABPresentsEditorWithMoodRowAndSaveButton() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]   // 隔离内存容器，呈现机制验收不受磁盘数据影响
        app.launch()

        let fab = app.buttons["新建时刻"]
        XCTAssertTrue(fab.waitForExistence(timeout: 10))
        fab.tap()

        XCTAssertTrue(app.buttons["editorMoodRow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editorTagRow"].exists)
        XCTAssertTrue(app.buttons["editorCancelButton"].exists)
        XCTAssertTrue(app.buttons["editorSaveButton"].exists)
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
}
