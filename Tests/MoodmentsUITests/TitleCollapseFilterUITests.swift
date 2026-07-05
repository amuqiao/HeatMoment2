import XCTest

/// 标题两态验收（见 04-screen-specs.md §4.1、08-architecture.md §2.2 裁决 B）：
/// 大标题态（滚到顶）纯场景标识、不可点、不触发筛选；上滑折叠后，收起态「时刻 ⌄」
/// 才是筛选入口，点击以就近浮窗（popover）打开 `FilterPanelView`。
final class TitleCollapseFilterUITests: XCTestCase {
    func testExpandedTitleTapDoesNotOpenFilter() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]   // 隔离内存容器，空态展开态可复现
        app.launch()

        let expandedTitle = app.staticTexts["timelineExpandedTitle"]
        XCTAssertTrue(expandedTitle.waitForExistence(timeout: 10))
        expandedTitle.tap()

        XCTAssertFalse(app.buttons["timelineCollapsedTitleButton"].exists)
        XCTAssertFalse(app.staticTexts["筛选 · 阶段5"].exists)
    }

    func testCollapsedTitleTapOpensFilterPopover() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedMoments"]   // 预置足量记录，使列表可滚动、标题可折叠
        app.launch()

        // 等待预置数据渲染完成再滑动，避免 seed 写入/@Query 刷新与滑动的竞态
        // （真实行为 isButton，其 accessibilityLabel 含标题「测试时刻 1」）。
        let seededRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "测试时刻 1"))
            .firstMatch
        XCTAssertTrue(seededRow.waitForExistence(timeout: 10))

        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        for _ in 0..<4 {
            scrollView.swipeUp()
        }

        let collapsedTitle = app.buttons["timelineCollapsedTitleButton"]
        XCTAssertTrue(collapsedTitle.waitForExistence(timeout: 5))
        collapsedTitle.tap()

        XCTAssertTrue(app.staticTexts["筛选 · 阶段5"].waitForExistence(timeout: 5))
    }
}
