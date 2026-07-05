import XCTest

/// 导航骨架验收（见 08-architecture.md §2.2）：点击悬浮新建按钮以任务卡片栈（`.sheet`）打开
/// 编辑器占位；用于验证 `AppRouter.rootSheet` 驱动的呈现机制跑通（真实编辑器内容见阶段3）。
final class EditorSheetPresentationUITests: XCTestCase {
    func testTapFABPresentsEditorSheet() {
        let app = XCUIApplication()
        app.launch()

        let fab = app.buttons["新建时刻"]
        XCTAssertTrue(fab.waitForExistence(timeout: 10))
        fab.tap()

        XCTAssertTrue(app.staticTexts["编辑器 · 阶段3"].waitForExistence(timeout: 5))
    }
}
