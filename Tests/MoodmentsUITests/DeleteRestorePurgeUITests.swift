import XCTest

/// 删除生命周期 + 预览呈现机制验收（见 `docs/product-mental-model.md` 公理3「删除是生命周期」、
/// `docs/design/04-screen-specs.md` §4.1/§4.14、`14-design-decisions.md` ADR-007）。
///
/// 用 `-uiTestSeedMoments` 预置 15 条真实可删记录（见 `UITestSupport`），定位其中标题固定为
/// 「测试时刻 1」的一条——用 `《测试时刻 1》` 精确匹配无障碍朗读文案中的标题片段，避免
/// `CONTAINS` 谓词误命中「测试时刻 10」~「测试时刻 15」（均以「测试时刻 1」为前缀）。
final class DeleteRestorePurgeUITests: XCTestCase {
    private let targetLabelFragment = "《测试时刻 1》"

    /// 首页左滑该行删除动作并点击 → 行从时间轴消失 → 打开设置「垃圾箱」入口 → 该记录出现在垃圾箱。
    func testSwipeDeleteMovesToTrash() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedMoments"]
        app.launch()

        swipeDeleteTargetRow(app)
        openTrash(app)

        XCTAssertTrue(
            app.staticTexts["测试时刻 1"].waitForExistence(timeout: 5),
            "软删除后该记录应出现在垃圾箱"
        )
    }

    /// 垃圾箱内右滑（leading）恢复 → 记录重新出现在时间轴。
    func testRestoreReturnsToTimeline() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedMoments"]
        app.launch()

        swipeDeleteTargetRow(app)
        openTrash(app)

        let trashRow = trashMomentRow(app)
        XCTAssertTrue(trashRow.waitForExistence(timeout: 5))
        trashRow.swipeRight()

        let restoreButton = app.buttons["恢复"]
        XCTAssertTrue(restoreButton.waitForExistence(timeout: 5))
        restoreButton.tap()

        // 垃圾箱内该记录消失（只剩这一条，恢复后垃圾箱应转入空态）。用垃圾箱空态的
        // `accessibilityIdentifier` 断言，而非按标题文案匹配——恢复后同一标题会重新出现在
        // 时间轴（此时仍在设置栈内、时间轴被模态遮住），避免与时间轴上同名标题产生歧义。
        XCTAssertTrue(
            app.staticTexts["trashEmptyState"].waitForExistence(timeout: 5),
            "恢复后垃圾箱应转入空态"
        )

        // 返回时间轴，记录重新出现。
        closeSettings(app)
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", targetLabelFragment))
                .firstMatch.waitForExistence(timeout: 5),
            "恢复后该记录应重新出现在时间轴"
        )
    }

    /// 垃圾箱内左滑（trailing）彻底删除 → 弹出二次确认 `.alert` → 确认后从垃圾箱消失（不可逆）。
    func testPurgeRequiresConfirmationAndRemoves() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedMoments"]
        app.launch()

        swipeDeleteTargetRow(app)
        openTrash(app)

        let trashRow = trashMomentRow(app)
        XCTAssertTrue(trashRow.waitForExistence(timeout: 5))
        trashRow.swipeLeft()

        let purgeButton = app.buttons["彻底删除"]
        XCTAssertTrue(purgeButton.waitForExistence(timeout: 5))
        purgeButton.tap()

        // 二次确认弹窗必须出现（彻底删除不可逆，见 04 §4.14）。
        let alert = app.alerts["彻底删除？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["彻底删除"].tap()

        XCTAssertTrue(
            app.staticTexts["trashEmptyState"].waitForExistence(timeout: 5),
            "确认彻底删除后垃圾箱应转入空态"
        )
        XCTAssertFalse(
            trashMomentRow(app).exists,
            "确认彻底删除后该记录不应再出现在垃圾箱"
        )
    }

    /// 预览是弹出的阅读卡片（进任务卡片栈），不是 push 页面跳转（依 ADR-007）：
    /// 点行出现 `momentPreviewCard`，只有「关闭」取消态而无 push 返回箭头；关闭后回到时间轴，
    /// 根层级的 FAB 仍在（证明时间轴主场景未被替换，只是叠了一张临时卡片）。
    func testPreviewIsCardNotPush() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedMoments"]
        app.launch()

        let row = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", targetLabelFragment))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()

        XCTAssertTrue(app.scrollViews["momentPreviewCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["momentPreviewCloseButton"].exists, "预览卡片应以「关闭」取消态呈现，而非 push 返回")
        XCTAssertFalse(app.navigationBars.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Back")).firstMatch.exists)

        app.buttons["momentPreviewCloseButton"].tap()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 5), "关闭预览卡片后应回到时间轴主场景（FAB 仍在）")
    }

    // MARK: - Helpers

    private func swipeDeleteTargetRow(_ app: XCUIApplication) {
        let row = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", targetLabelFragment))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()

        let deleteButton = app.buttons["timelineSwipeDeleteButton"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", targetLabelFragment))
                .firstMatch.waitForExistence(timeout: 5),
            "软删除后该行应从时间轴消失"
        )
    }

    private func openTrash(_ app: XCUIApplication) {
        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        let trashRow = app.buttons["settingsTrashRow"]
        XCTAssertTrue(trashRow.waitForExistence(timeout: 5))
        trashRow.tap()
    }

    private func trashMomentRow(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                    "trashRow-",
                    "测试时刻 1"
                )
            )
            .firstMatch
    }

    private func closeSettings(_ app: XCUIApplication) {
        // 垃圾箱是设置栈内的子页，需先返回设置根页再关闭 sheet。
        if app.navigationBars.buttons.element(boundBy: 0).exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        let closeButton = app.buttons["关闭"]
        if closeButton.waitForExistence(timeout: 5) {
            closeButton.tap()
        }
    }
}
