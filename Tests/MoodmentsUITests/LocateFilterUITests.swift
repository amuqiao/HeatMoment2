import XCTest

/// 「回看/筛选/定位」UI 集成验收（见 `docs/product-mental-model.md` 公理2「定位 ≠ 筛选」、
/// `docs/current/implementation-truth.md` §4.1/§4.2/§4.3，`docs/plans/implementation-plan.md` 阶段5）：
/// 阶段5落地的筛选就近浮窗 + 上下文标记 + 热力图定位是本阶段头牌功能，此前只有单元测试
/// （`LocateVsFilterTests`）覆盖谓词/纯函数层面，缺 XCUITest 端到端验收，此文件补齐。
///
/// 复用 `-uiTestSeedMoments`（见 `UITestSupport`）：15 条记录心情均为默认 `.normal`
/// （rawValue 0），足以稳定支撑本文件两条断言（筛选「种子里不存在的心情」、定位到有色日期格），
/// 不需要额外新增变体种子。
final class LocateFilterUITests: XCTestCase {
    /// 筛选到种子里不存在的心情 → 展示筛选空态 + 出现心情上下文筛选标记；
    /// 移除该标记 → 退出空态、记录回归（回归验证「移除筛选标记」这一真实交互路径，
    /// 而非只是重新打开面板取消勾选）。
    func testFilterAbsentMoodShowsEmptyStateThenMarkerRemovalRestoresRecords() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedMoments"]
        app.launch()

        let seededRowQuery = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "测试时刻 1"))
        XCTAssertTrue(seededRowQuery.firstMatch.waitForExistence(timeout: 10))

        // 与 `TitleCollapseFilterUITests` 同法：先滑动折叠标题，收起态「时刻 ⌄」才是筛选入口。
        for _ in 0..<4 {
            app.swipeUp()
        }
        let collapsedTitle = app.buttons["timelineCollapsedTitleButton"]
        XCTAssertTrue(collapsedTitle.waitForExistence(timeout: 5))
        collapsedTitle.tap()

        // 种子记录心情均为默认 `.normal`（rawValue 0），选「开心」（rawValue 1）保证种子里
        // 必然没有命中，筛选结果必为空态——不依赖任何脆弱的具体计数假设。
        let happyOption = app.buttons["filterMoodOption-1"]
        XCTAssertTrue(happyOption.waitForExistence(timeout: 5))
        happyOption.tap()
        // 交互模型 v2：筛选已从就近浮窗改为半屏 sheet（`.presentationDetents([.medium, .large])`），
        // sheet 不因点选自动收起（就地即时生效、点选即写 `activeFilter`），点「完成」收起 sheet
        // 后再验证 sheet 之下（此前被模态遮挡）的时间轴筛选态。
        dismissFilterSheet(app)

        XCTAssertTrue(
            app.staticTexts["timelineFilteredEmptyState"].waitForExistence(timeout: 5),
            "筛选到种子里不存在的心情应展示筛选空态"
        )
        let moodMarker = app.descendants(matching: .any).matching(identifier: "contextMarkerMood")
            .firstMatch
        XCTAssertTrue(moodMarker.waitForExistence(timeout: 5), "筛选生效后应出现心情筛选上下文标记")

        // `contextMarkerMood` 由 `.accessibilityElement(children: .combine)` 合并文案与移除按钮，
        // 但实测其内部移除按钮（系统 `xmark.circle.fill` 图标）仍作为独立无障碍元素可寻址，
        // 直接在该标记范围内定位它并点击，比猜测几何坐标更稳定。
        let removeButton = moodMarker.buttons["xmark.circle.fill"]
        XCTAssertTrue(removeButton.waitForExistence(timeout: 5), "心情筛选标记内应能定位到移除按钮")
        removeButton.tap()

        XCTAssertTrue(waitForNonexistence(of: moodMarker, timeout: 5), "移除心情筛选标记后标记本身应消失")
        XCTAssertFalse(
            app.staticTexts["timelineFilteredEmptyState"].waitForExistence(timeout: 3),
            "移除筛选标记后应退出筛选空态"
        )
        XCTAssertTrue(
            seededRowQuery.firstMatch.waitForExistence(timeout: 5),
            "移除筛选标记后种子记录应重新出现在时间轴"
        )
    }

    /// 打开热力图 → 点一个有色（有记录）日期格 → 出现时间上下文标记（定位态，见 docs/current/implementation-truth.md §4.3）。
    func testLocateHeatmapDayCellShowsTimeContextMarker() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedMoments"]
        app.launch()

        let seededRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "测试时刻 1"))
            .firstMatch
        XCTAssertTrue(seededRow.waitForExistence(timeout: 10))

        let heatmapButton = app.buttons["年度心情热力图"]
        XCTAssertTrue(heatmapButton.waitForExistence(timeout: 5))
        heatmapButton.tap()

        XCTAssertTrue(app.buttons["heatmapCloseButton"].waitForExistence(timeout: 5))

        // 15 条种子记录集中在最近几小时内，年度热力图上必至少有一个「有记录」（可点）日期格。
        let dayCell = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "heatmapDayCell-"))
            .firstMatch
        XCTAssertTrue(dayCell.waitForExistence(timeout: 5), "种子记录应至少产生一个有色（可点）日期格")
        dayCell.tap()

        app.buttons["heatmapCloseButton"].tap()

        let timeMarker = app.descendants(matching: .any).matching(identifier: "contextMarkerTime")
            .firstMatch
        XCTAssertTrue(timeMarker.waitForExistence(timeout: 5), "点选有记录的日期格后应出现时间上下文标记")
    }

    /// 打开热力图 → 点一个月份标签 → 出现月份粒度的时间上下文标记。
    func testLocateHeatmapMonthLabelShowsMonthContextMarker() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedMoments"]
        app.launch()

        let seededRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "测试时刻 1"))
            .firstMatch
        XCTAssertTrue(seededRow.waitForExistence(timeout: 10))

        let heatmapButton = app.buttons["年度心情热力图"]
        XCTAssertTrue(heatmapButton.waitForExistence(timeout: 5))
        heatmapButton.tap()

        XCTAssertTrue(app.buttons["heatmapCloseButton"].waitForExistence(timeout: 5))

        let currentYear = Calendar.current.component(.year, from: Date())
        let currentMonth = Calendar.current.component(.month, from: Date())
        let monthWithoutSeedRecords = currentMonth == 1 ? 2 : 1
        XCTAssertFalse(
            app.buttons["heatmapMonthLabel-\(currentYear)-\(monthWithoutSeedRecords)"].exists,
            "无记录月份不应提供可点击月份定位入口"
        )
        XCTAssertTrue(
            app.buttons["heatmapMonthLabel-\(currentYear)-\(currentMonth)"].waitForExistence(
                timeout: 5),
            "有记录月份应提供可点击月份定位入口"
        )

        let monthLabel = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "heatmapMonthLabel-"))
            .firstMatch
        XCTAssertTrue(monthLabel.waitForExistence(timeout: 5), "热力图应提供可点击月份标签")
        monthLabel.tap()

        app.buttons["heatmapCloseButton"].tap()

        let timeMarker = app.descendants(matching: .any).matching(identifier: "contextMarkerTime")
            .firstMatch
        XCTAssertTrue(timeMarker.waitForExistence(timeout: 5), "点选月份后应出现时间上下文标记")
        XCTAssertTrue(
            timeMarker.label.contains("月"),
            "月份定位标记应表达月份上下文"
        )
    }

    // MARK: - Helpers

    /// 收起筛选半屏 sheet：点 sheet 右上「完成」（`filterDoneButton`）。sheet 是模态，收起后
    /// 其下的时间轴才重新进入无障碍树可被断言（见调用处说明）。
    private func dismissFilterSheet(_ app: XCUIApplication) {
        let doneButton = app.buttons["filterDoneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "筛选 sheet 点选条件后不应自动关闭")
        doneButton.tap()
    }

    /// 等待某元素从无障碍树消失（`XCUIElement` 无内置 `waitForNonexistence`，用谓词表达式等待）。
    private func waitForNonexistence(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
