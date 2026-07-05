import XCTest

/// 空态验收（见 02-information-architecture.md、04-screen-specs.md §4.1）：首次启动、
/// 时间轴无真实记录时，展示 3 条不可删/不可编辑的预置引导 Moment（见 `GuidedMoment`）。
final class TimelineEmptyStateUITests: XCTestCase {
    func testEmptyStateShowsThreeGuidedMoments() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]   // 隔离内存空容器，确保命中空态引导、不依赖磁盘残留
        app.launch()

        XCTAssertTrue(app.staticTexts["马上创建"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["什么是时刻?"].exists)
        XCTAssertTrue(app.staticTexts["欢迎来到时刻~"].exists)
    }
}
