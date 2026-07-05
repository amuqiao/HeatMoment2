import XCTest

/// App 启动冒烟：启动后进入时间轴首页（首页大标题「时刻」可见）。
/// 空态 3 引导、标题折叠筛选等细化断言见 `TimelineEmptyStateUITests` / `TitleCollapseFilterUITests`。
final class AppLaunchUITests: XCTestCase {
    func testAppLaunchesIntoTimeline() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["时刻"].firstMatch.waitForExistence(timeout: 10))
    }
}
