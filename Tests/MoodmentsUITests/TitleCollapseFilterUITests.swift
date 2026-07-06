import XCTest

/// 标题两态验收（见 04-screen-specs.md §4.1、08-architecture.md §2.2 裁决 B）：
/// 大标题态（滚到顶）纯场景标识、不可点、不触发筛选；上滑折叠后，收起态「时刻 ⌄」
/// 才是筛选入口，点击以就近浮窗（popover）打开 `FilterPanelView`。
///
/// 阶段5起 `FilterPanelView` 落地真实内容（旧阶段2占位文案「筛选 · 阶段5」已随真实内容落地
/// 失效，同 `EditorSheetPresentationUITests` 头部注释所述取舍），断言改为真实面板的
/// 心情候选行（`filterMoodOption-<rawValue>`）。
final class TitleCollapseFilterUITests: XCTestCase {
    func testExpandedTitleTapDoesNotOpenFilter() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]   // 隔离内存容器，空态展开态可复现
        app.launch()

        let expandedTitle = app.staticTexts["timelineExpandedTitle"]
        XCTAssertTrue(expandedTitle.waitForExistence(timeout: 10))
        expandedTitle.tap()

        XCTAssertFalse(app.buttons["timelineCollapsedTitleButton"].exists)
        XCTAssertFalse(app.buttons["filterMoodOption-0"].exists)
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

        // 阶段 4 起时间轴容器由 `ScrollView` 迁移为 `List`（见 `TimelineHomeView`，左滑删除用
        // 成熟方案 `.swipeActions`）：`List` 底层由 `UICollectionView` 承载，XCUITest 不再将其
        // 归类到 `app.scrollViews`。直接对 `app` 派发滑动手势（作用于前台窗口可见区域），
        // 不依赖某个具体元素类型查询，规避该分类差异。
        for _ in 0..<4 {
            app.swipeUp()
        }

        let collapsedTitle = app.buttons["timelineCollapsedTitleButton"]
        XCTAssertTrue(collapsedTitle.waitForExistence(timeout: 5))
        collapsedTitle.tap()

        // 面板内应有 8 个心情候选行之一（如 rawValue 1「开心」）。
        XCTAssertTrue(app.buttons["filterMoodOption-1"].waitForExistence(timeout: 5))
    }
}
