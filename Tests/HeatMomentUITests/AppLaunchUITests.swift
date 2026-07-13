import XCTest

/// App 启动冒烟：启动后进入时间轴首页（首页大标题「时刻」可见）。
/// 空态 3 引导、标题折叠筛选等细化断言见 `TimelineEmptyStateUITests` / `TitleCollapseFilterUITests`。
final class AppLaunchUITests: XCTestCase {
    func testAppLaunchesIntoTimeline() {
        let app = XCUIApplication.heatMoment()
        app.launchArguments = ["-uiTestReset"]  // 隔离内存 canonical runtime，空态可复现、不依赖磁盘残留
        app.launch()
        XCTAssertTrue(app.staticTexts["timelineExpandedTitle"].waitForExistence(timeout: 10))
    }
}
