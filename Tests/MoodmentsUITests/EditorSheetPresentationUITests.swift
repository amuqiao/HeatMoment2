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
}
