import XCTest

/// 标题两态验收（见 04-screen-specs.md §4.1、08-architecture.md §2.2 裁决 B）：
/// 大标题态（滚到顶）纯场景标识、不可点、不触发筛选；上滑折叠后，收起态「时刻 ⌄」
/// 才是筛选入口，点击以**半屏 bottom sheet**（交互模型 v2，从旧就近浮窗解耦，见
/// `docs/design/14-design-decisions.md` ADR-006 `[AMENDED v2]`）打开 `FilterPanelView`。
///
/// `FilterPanelView` 落地真实内容（旧占位文案「筛选 · 阶段5」已失效），断言用真实面板的
/// 心情候选 chip（`filterMoodOption-<rawValue>`）与标签 chip（`filterTagOption-*`）。
final class TitleCollapseFilterUITests: XCTestCase {
    func testExpandedTitleTapDoesNotOpenFilter() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]  // 隔离内存容器，空态展开态可复现
        app.launch()

        let expandedTitle = app.staticTexts["timelineExpandedTitle"]
        XCTAssertTrue(expandedTitle.waitForExistence(timeout: 10))
        expandedTitle.tap()

        XCTAssertFalse(app.buttons["timelineCollapsedTitleButton"].exists)
        XCTAssertFalse(app.buttons["filterMoodOption-0"].exists)
    }

    func testCollapsedTitleTapOpensFilterSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedMoments"]  // 预置足量记录，使列表可滚动、标题可折叠
        app.launch()

        collapseTitleAndOpenFilter(app)

        // 半屏 sheet 内应有 8 个心情候选行之一（如 rawValue 1「开心」）。
        XCTAssertTrue(app.buttons["filterMoodOption-1"].waitForExistence(timeout: 5))
    }

    /// 筛选 sheet 只负责选择已有条件，不提供标签新增入口；已有标签点选仍即时写入筛选条件。
    func testFilterSheetHidesTagCreateEntryAndExistingTagStillFilters() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedMoments"]
        app.launch()

        collapseTitleAndOpenFilter(app)

        XCTAssertFalse(app.buttons["filterAddTagButton"].exists, "筛选 sheet 不应暴露标签新增入口")
        XCTAssertFalse(app.textFields["tagCreateNameField"].exists, "筛选 sheet 不应打开新建标签表单")
        XCTAssertFalse(app.buttons["tagManageAddButton"].exists, "筛选 sheet 不应复用标签管理新增按钮")
        let createTagButton = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "新建标签"))
            .firstMatch
        XCTAssertFalse(
            createTagButton.exists,
            "筛选 sheet 不应提供新建标签按钮"
        )

        let workTagOption = app.buttons["filterTagOption-工作"]
        XCTAssertTrue(workTagOption.waitForExistence(timeout: 5))
        workTagOption.tap()

        dismissFilterSheet(app)

        let workMarker = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "#工作"))
            .firstMatch
        XCTAssertTrue(
            workMarker.waitForExistence(timeout: 5),
            "选择已有标签应立即写入筛选条件（出现 #工作 上下文标记）"
        )
        XCTAssertTrue(
            app.staticTexts["timelineFilteredEmptyState"].waitForExistence(timeout: 5),
            "种子记录均未挂标签，筛选工作标签应命中 0 条、进入筛选空态"
        )
    }

    /// 收起筛选半屏 sheet：点「完成」（`filterDoneButton`）。点选条件后 sheet 必须仍保持打开，
    /// 这里找不到完成按钮即视为“点选后自动关闭”的回归。
    private func dismissFilterSheet(_ app: XCUIApplication) {
        let doneButton = app.buttons["filterDoneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "筛选 sheet 点选条件后不应自动关闭")
        doneButton.tap()
    }

    // MARK: - Helpers

    /// 等待预置数据渲染 → 上滑折叠标题 → 点收起态「时刻 ⌄」打开筛选 sheet。
    private func collapseTitleAndOpenFilter(_ app: XCUIApplication) {
        // 等待预置数据渲染完成再滑动，避免 seed 写入/@Query 刷新与滑动的竞态
        // （真实行为 isButton，其 accessibilityLabel 含标题「测试时刻 1」）。
        let seededRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "测试时刻 1"))
            .firstMatch
        XCTAssertTrue(seededRow.waitForExistence(timeout: 10))

        // 时间轴容器为 `List`（底层 `UICollectionView`），XCUITest 不归类到 `app.scrollViews`；
        // 直接对 `app` 派发滑动手势（作用于前台窗口可见区域），规避元素类型查询差异。
        for _ in 0..<4 {
            app.swipeUp()
        }

        let collapsedTitle = app.buttons["timelineCollapsedTitleButton"]
        XCTAssertTrue(collapsedTitle.waitForExistence(timeout: 5))
        collapsedTitle.tap()
    }
}
