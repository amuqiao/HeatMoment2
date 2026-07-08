import XCTest

/// 标签管理验收（见 `docs/design/04-screen-specs.md` §4.13、`docs/product-mental-model.md`
/// 公理7「标签是归类不是所有权」，`docs/plans/implementation-plan.md` 阶段6）：
/// 删除标签清理筛选态陈旧 id、重命名、删标签不删时刻。
///
/// 默认标签「工作/生活/健康」由 `DefaultTagSeeder` 在每次 UI 测试冷启动预置一次（首启标记经
/// `UITestSupport.resetDefaultTagSeedFlagIfUITestRun()` 在 `init()` 复位，等价于每次都是「真正
/// 首启」，见 `docs/design/07-data-persistence.md` §4、`App/RootView.swift`），本文件全程依赖
/// 该预置、不需要额外的 `UITestSupport` 标签种子钩子。
final class TagManageUITests: XCTestCase {
    /// 标签新增归属设置页标签管理：免费额度未满时，右上「+」打开新建标签卡片，保存后回到列表。
    func testCreateTagFromTagManageAddsRow() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSkipDefaultTags"]
        app.launch()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 10))
        openTagManage(app)

        XCTAssertTrue(app.staticTexts["tagManageEmptyState"].waitForExistence(timeout: 5))

        let addButton = app.buttons["tagManageAddButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let nameField = app.textFields["tagCreateNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("旅行")

        app.buttons["tagCreateSaveButton"].tap()

        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "旅行")).firstMatch
                .waitForExistence(timeout: 5),
            "标签管理保存后应展示新建标签"
        )
        XCTAssertFalse(app.textFields["tagCreateNameField"].exists, "保存成功后新建标签卡片应关闭")
    }

    /// 筛选态下删除正在被筛选的标签 → 上下文标记消失、筛选态清空、记录重新可见
    /// （阶段6计划决策5：`TimelineModel.discardFilterTag`）。种子记录（`-uiTestSeedMoments`）
    /// 均未挂任何标签，筛选「工作」必命中 0 条（不依赖脆弱的具体计数假设，与
    /// `LocateFilterUITests` 同一手法）。
    func testDeleteTagClearsActiveFilterAndRestoresResults() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedMoments"]
        app.launch()

        let seededRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "测试时刻 1"))
            .firstMatch
        XCTAssertTrue(seededRow.waitForExistence(timeout: 10))

        for _ in 0..<4 { app.swipeUp() }
        let collapsedTitle = app.buttons["timelineCollapsedTitleButton"]
        XCTAssertTrue(collapsedTitle.waitForExistence(timeout: 5))
        collapsedTitle.tap()

        let workTagOption = app.buttons["filterTagOption-工作"]
        XCTAssertTrue(workTagOption.waitForExistence(timeout: 5))
        workTagOption.tap()
        // 交互模型 v2：筛选改为半屏 sheet（见 `TitleCollapseFilterUITests`），点「完成」收起后
        // 才能断言 sheet 之下的时间轴筛选态；这里的标签选择是筛选面板（sheet），非编辑器标签浮窗。
        dismissFilterSheet(app)

        XCTAssertTrue(
            app.staticTexts["timelineFilteredEmptyState"].waitForExistence(timeout: 5),
            "种子记录均未挂标签，筛选「工作」应命中 0 条"
        )
        let tagMarker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "contextMarkerTag-"))
            .firstMatch
        XCTAssertTrue(tagMarker.waitForExistence(timeout: 5), "筛选生效后应出现标签筛选上下文标记")

        openTagManage(app)

        // 用 `tagManageRow-` 标识前缀限定查找范围：仅按标签名 `label CONTAINS` 会误命中时间轴上
        // 仍存在于无障碍树里的同名筛选标记 chip（`contextMarkerTag-...`，label 同为「#工作」），
        // 导致 swipe/tap 打到错误元素（曾实测复现）。
        let workRow = app.buttons
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "tagManageRow-", "工作")
            )
            .firstMatch
        XCTAssertTrue(workRow.waitForExistence(timeout: 5))
        workRow.swipeLeft()
        let deleteButton = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "tagManageDeleteButton-"))
            .firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        XCTAssertTrue(waitForNonexistence(of: workRow, timeout: 5), "删除后该标签行应从标签管理列表消失")

        closeSettings(app)

        XCTAssertTrue(waitForNonexistence(of: tagMarker, timeout: 5), "删除该标签后其筛选标记应消失")
        XCTAssertFalse(
            app.staticTexts["timelineFilteredEmptyState"].waitForExistence(timeout: 3),
            "筛选清空后应退出筛选空态"
        )
        XCTAssertTrue(seededRow.waitForExistence(timeout: 5), "筛选清空后种子记录应重新出现")
    }

    /// 点击标签行进入重命名（预填原名）→ 保存后列表展示新名称，旧名称不再出现。
    func testRenameTagUpdatesDisplayedName() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 10))
        openTagManage(app)

        let lifeRow = app.buttons
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "tagManageRow-", "生活")
            )
            .firstMatch
        XCTAssertTrue(lifeRow.waitForExistence(timeout: 5))
        lifeRow.tap()

        let nameField = app.textFields["tagCreateNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(nameField.value as? String, "生活", "重命名态应预填原名")

        replaceText(in: nameField, with: "兴趣")
        app.buttons["tagCreateSaveButton"].tap()

        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "兴趣")).firstMatch
                .waitForExistence(timeout: 5),
            "重命名后列表应展示新名称"
        )
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "生活")).firstMatch
                .waitForExistence(timeout: 3),
            "重命名后不应再展示旧名称"
        )
    }

    /// 删标签只解除关联，不删时刻内容（公理7）：先建一条挂了「工作」标签的时刻，删除该标签后
    /// 时刻标题仍完整出现在时间轴。
    func testDeletingTagPreservesMomentContent() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        let fab = app.buttons["新建时刻"]
        XCTAssertTrue(fab.waitForExistence(timeout: 10))
        fab.tap()

        let tagRow = app.buttons["editorTagRow"]
        XCTAssertTrue(tagRow.waitForExistence(timeout: 5))
        tagRow.tap()

        let workTagOption = app.buttons["tagOption-工作"]
        XCTAssertTrue(workTagOption.waitForExistence(timeout: 5))
        workTagOption.tap()
        dismissPopoverIfPresent(app)

        let titleField = app.textFields["editorTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("带标签的时刻")

        app.buttons["editorSaveButton"].tap()

        let momentRow = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "带标签的时刻"))
            .firstMatch
        XCTAssertTrue(momentRow.waitForExistence(timeout: 5), "保存后该时刻应出现在时间轴")

        openTagManage(app)

        let workRow = app.buttons
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "tagManageRow-", "工作")
            )
            .firstMatch
        XCTAssertTrue(workRow.waitForExistence(timeout: 5))
        workRow.swipeLeft()
        app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "tagManageDeleteButton-"))
            .firstMatch.tap()

        closeSettings(app)

        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "带标签的时刻")).firstMatch
                .waitForExistence(timeout: 5),
            "删除标签后该时刻内容应完整保留在时间轴（删标签不删时刻，公理7）"
        )
    }

    /// 重命名撞已存在标签名 → 应用层查重命中 `tagNameConflict`，走统一 `ErrorPresenter` 呈现
    /// 可见错误提示、不静默、不 dismiss（见 `TagCreateSheetView.save()`；本用例同时验证阶段6
    /// review 修复项1：`TagCreateSheetView` 作为最前 sheet 自行挂 `.userFacingErrorAlert`，
    /// 否则父级 `SettingsSheetView` 的 alert 弹不到它上面、用户界面会毫无反应）。
    func testRenameTagToExistingNameShowsVisibleError() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 10))
        openTagManage(app)

        let lifeRow = app.buttons
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "tagManageRow-", "生活")
            )
            .firstMatch
        XCTAssertTrue(lifeRow.waitForExistence(timeout: 5))
        lifeRow.tap()

        let nameField = app.textFields["tagCreateNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(nameField.value as? String, "生活", "重命名态应预填原名")

        // 「工作」是 `DefaultTagSeeder` 预置的既有标签名，撞名。
        replaceText(in: nameField, with: "工作")
        app.buttons["tagCreateSaveButton"].tap()

        XCTAssertTrue(
            app.staticTexts["出错了"].waitForExistence(timeout: 5),
            "撞名应弹出可见错误提示，而不是界面毫无反应"
        )
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "已存在")).firstMatch
                .waitForExistence(timeout: 3),
            "错误提示文案应说明标签名已存在"
        )

        app.buttons["好的"].tap()

        // 撞名不 dismiss——输入内容保留在原地供用户重试。
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "撞名保存失败后不应 dismiss，应留在原卡片供重试")
        XCTAssertEqual(nameField.value as? String, "工作", "撞名失败后应保留用户已输入的内容，不清空/不回填原值")
    }

    // MARK: - Helpers

    private func openTagManage(_ app: XCUIApplication) {
        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()

        let tagManageRow = app.buttons["settingsTagManageRow"]
        XCTAssertTrue(tagManageRow.waitForExistence(timeout: 5))
        tagManageRow.tap()
    }

    private func closeSettings(_ app: XCUIApplication) {
        // 标签管理是设置栈内的子页，需先返回设置根页，再使用系统下滑关闭设置 sheet。
        if app.navigationBars.buttons.element(boundBy: 0).exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        dismissSettingsSheet(app)
    }

    private func dismissSettingsSheet(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["settingsTagManageRow"].waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.90))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func replaceText(in field: XCUIElement, with newValue: String) {
        field.tap()
        if let currentValue = field.value as? String, !currentValue.isEmpty {
            let deleteString = String(
                repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
            field.typeText(deleteString)
        }
        field.typeText(newValue)
    }

    /// 若就近浮窗仍在（未自动收起）则点外部收起；已收起则直接跳过，不视为失败
    /// （见 `LocateFilterUITests` 同名 helper 的说明）。**仅用于仍为就近浮窗的编辑器标签选择**
    /// （`tagOption-*`）；筛选面板已在交互模型 v2 改为半屏 sheet，用下方 `dismissFilterSheet`。
    private func dismissPopoverIfPresent(_ app: XCUIApplication) {
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        guard dismissRegion.waitForExistence(timeout: 2) else { return }
        dismissRegion.tap()
    }

    /// 收起筛选半屏 sheet：点「完成」（`filterDoneButton`）。sheet 是模态，收起后其下的时间轴
    /// 才重新进入无障碍树可被断言（交互模型 v2 筛选呈现变更，见 `TitleCollapseFilterUITests`）。
    private func dismissFilterSheet(_ app: XCUIApplication) {
        let doneButton = app.buttons["filterDoneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5), "筛选 sheet 点选条件后不应自动关闭")
        doneButton.tap()
    }

    private func waitForNonexistence(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
