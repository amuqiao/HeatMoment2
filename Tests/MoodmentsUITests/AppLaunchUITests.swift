import XCTest

/// 阶段 0 UI 冒烟：App 能启动且显示占位标题「时刻」。
final class AppLaunchUITests: XCTestCase {
    func testAppLaunchesAndShowsTitle() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["时刻"].waitForExistence(timeout: 10))
    }
}
