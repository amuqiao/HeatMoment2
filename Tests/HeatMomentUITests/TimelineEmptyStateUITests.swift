import XCTest

/// 首启默认资料库验收：新安装会创建 3 条真实 Moment，而不是独立展示模型。
final class TimelineEmptyStateUITests: XCTestCase {
    func testFirstLaunchShowsThreeEditableDefaultMoments() {
        let app = XCUIApplication.heatMoment()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        XCTAssertTrue(app.staticTexts["马上创建"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["什么是时刻?"].exists)
        XCTAssertTrue(app.staticTexts["欢迎来到心绪日记~"].exists)

        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "马上创建"))
            .firstMatch
            .tap()
        XCTAssertTrue(app.staticTexts["马上创建"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["编辑"].waitForExistence(timeout: 5))
    }
}
