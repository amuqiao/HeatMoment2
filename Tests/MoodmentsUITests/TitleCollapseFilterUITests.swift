import XCTest

/// 标题两态验收（见 04-screen-specs.md §4.1、08-architecture.md §2.2 裁决 B）：
/// 大标题态（滚到顶）纯场景标识、不可点、不触发筛选；上滑折叠后，收起态「时刻 ⌄」
/// 才是筛选入口，点击以**半屏 bottom sheet**（交互模型 v2，从旧就近浮窗解耦，见
/// `docs/design/14-design-decisions.md` ADR-006 `[AMENDED v2]`）打开 `FilterPanelView`。
///
/// `FilterPanelView` 落地真实内容（旧占位文案「筛选 · 阶段5」已失效），断言用真实面板的
/// 心情候选行（`filterMoodOption-<rawValue>`）与标签「新增标签」入口（`filterAddTagButton`）。
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

    func testCollapsedTitleTapOpensFilterSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedMoments"]   // 预置足量记录，使列表可滚动、标题可折叠
        app.launch()

        collapseTitleAndOpenFilter(app)

        // 半屏 sheet 内应有 8 个心情候选行之一（如 rawValue 1「开心」）。
        XCTAssertTrue(app.buttons["filterMoodOption-1"].waitForExistence(timeout: 5))
    }

    /// 「新增标签子级 sheet」建完自动选中可筛（见 04 §4.2「新增标签子级 sheet」——本次交互模型 v2
    /// 新增的核心行为；多标签 AND 组合语义本身不变、由单元测试 `MultiTagFilterTests` 覆盖）：
    /// 在筛选 sheet 内点「+ 新增标签」→ 第二层 `TagCreateSheetView` 建一个种子里不存在的新标签
    /// →「旅行」自动并入 `activeFilter.tagIDs` 并**即时生效**（时间轴出现 `#旅行` 筛选上下文标记
    /// + 命中 0 条进入筛选空态）。
    ///
    /// 说明：新标签自动加入筛选后列表变空、标题去折叠 → 承载筛选 sheet 的收起态入口卸载，sheet
    /// 随之自动收起（与旧就近浮窗遇列表大改自动收起同理）；`dismissFilterSheet` 做「仍在则显式
    /// 收起」的兼容，之后断言 sheet 之下（此前被模态遮挡）的时间轴结果，稳定不依赖某一种收起时序。
    func testAddTagFromFilterSheetAutoSelectsForFiltering() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedMoments"]
        app.launch()

        collapseTitleAndOpenFilter(app)

        // 「+ 新增标签」→ 第二层新建标签 sheet。
        let addTagButton = app.buttons["filterAddTagButton"]
        XCTAssertTrue(addTagButton.waitForExistence(timeout: 5))
        addTagButton.tap()

        let nameField = app.textFields["tagCreateNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("旅行")   // 预置标签为 工作/生活/健康，不撞名；种子记录均未挂标签
        app.buttons["tagCreateSaveButton"].tap()

        dismissFilterSheet(app)

        // 出现「#旅行」筛选上下文标记 == 新标签已自动加入筛选条件；进入筛选空态 == 已即时生效可筛。
        let travelMarker = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "#旅行"))
            .firstMatch
        XCTAssertTrue(
            travelMarker.waitForExistence(timeout: 5),
            "新建标签应自动加入筛选条件（出现 #旅行 上下文标记）"
        )
        XCTAssertTrue(
            app.staticTexts["timelineFilteredEmptyState"].waitForExistence(timeout: 5),
            "筛选新建标签（种子无该标签）应命中 0 条、进入筛选空态（即时生效可筛）"
        )
    }

    /// 收起筛选半屏 sheet：点「完成」（`filterDoneButton`）；若已自动收起（如筛选致列表变空、
    /// 标题去折叠使入口卸载）则直接跳过，不视为失败。sheet 是模态，收起后其下的时间轴才重新
    /// 进入无障碍树可被断言。
    private func dismissFilterSheet(_ app: XCUIApplication) {
        let doneButton = app.buttons["filterDoneButton"]
        guard doneButton.waitForExistence(timeout: 5) else { return }
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
