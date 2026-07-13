import XCTest

/// 新建时刻完整流程验收（见 `docs/product-mental-model.md` §3.1、
/// `docs/plans/implementation-plan.md` 阶段 3 验收：情绪→标签→日期→标题→保存→出现在时间轴）。
///
/// 标签选择用首启默认预置的标签（工作/生活/健康，见 `DefaultTagSeeder`），不新建标签
/// （见阶段 3 计划决策4）。日期/时间就近浮窗的验证只做「打开→控件存在→点浮窗外部收起」，
/// 不深入操作系统 `DatePicker` 内部的具体日期格（图形日历控件的可访问性标签依赖当前系统
/// 区域/月份布局，逐日选择在 `XCUITest` 中天然脆弱，此处按「跑通就近浮窗打开/收起」验收，
/// 已在完成报告中说明该取舍）。
final class CreateMomentFlowUITests: XCTestCase {
    func testFullCreateFlowAppendsBubbleToTimeline() {
        let app = XCUIApplication.heatMoment()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        let fab = app.buttons["新建时刻"]
        XCTAssertTrue(fab.waitForExistence(timeout: 10))
        fab.tap()

        // 情绪：打开就近浮窗，选「开心」（Mood.happy.rawValue == 1）。
        let moodRow = app.buttons["editorMoodRow"]
        XCTAssertTrue(moodRow.waitForExistence(timeout: 5))
        moodRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["editorMoodPickerMenu"].exists)
        XCTAssertFalse(app.otherElements["PopoverDismissRegion"].exists)
        let happyOption = app.buttons["moodOption-1"]
        XCTAssertTrue(happyOption.waitForExistence(timeout: 5))
        XCTAssertTrue(happyOption.isHittable)
        happyOption.tap()

        // 标签：打开就近浮窗，选预置标签「工作」（不新建，见类型头部说明）。
        let tagRow = app.buttons["editorTagRow"]
        XCTAssertTrue(tagRow.waitForExistence(timeout: 5))
        tagRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["editorTagPickerMenu"].exists)
        XCTAssertFalse(app.otherElements["PopoverDismissRegion"].exists)
        let workTagOption = app.buttons["tagOption-工作"]
        XCTAssertTrue(workTagOption.waitForExistence(timeout: 5))
        XCTAssertTrue(workTagOption.isHittable)
        workTagOption.tap()
        dismissEditorFloatingPicker(app)

        // 日期：打开就近浮窗，确认日历控件出现，再点外部收起（见类型头部关于日期格自动化的说明）。
        let dateChip = app.buttons["editorDateChip"]
        XCTAssertTrue(dateChip.waitForExistence(timeout: 5))
        dateChip.tap()
        XCTAssertTrue(app.datePickers["editorDatePicker"].waitForExistence(timeout: 5))
        dismissSystemPopover(app)

        // 时间：只验收就近浮窗打开/收起；具体滚轮即时回写由 `OccurredAtComposerTests` 锁定。
        let timeChip = app.buttons["editorTimeChip"]
        XCTAssertTrue(timeChip.waitForExistence(timeout: 5))
        timeChip.tap()
        XCTAssertTrue(app.datePickers["editorTimePicker"].waitForExistence(timeout: 5))
        dismissSystemPopover(app)

        // 标题
        let titleField = app.textFields["editorTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("今天很开心")

        // 保存
        let saveButton = app.buttons["editorSaveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        // 回到时间轴，新气泡出现（标题「今天很开心」）。
        XCTAssertTrue(app.staticTexts["今天很开心"].waitForExistence(timeout: 5))
    }

    /// 标签创建归属设置页标签管理；编辑器标签浮窗只消费已有标签，不提供临时创建入口。
    func testEditorTagPickerOnlyConsumesExistingTags() {
        let app = XCUIApplication.heatMoment()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        let fab = app.buttons["新建时刻"]
        XCTAssertTrue(fab.waitForExistence(timeout: 10))
        fab.tap()

        let tagRow = app.buttons["editorTagRow"]
        XCTAssertTrue(tagRow.waitForExistence(timeout: 5))
        tagRow.tap()

        XCTAssertTrue(app.buttons["tagOption-工作"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.textFields["tagCreateNameField"].exists,
            "编辑器标签浮窗不应打开新建标签表单"
        )
        XCTAssertFalse(
            app.buttons["tagManageAddButton"].exists,
            "编辑器标签浮窗不应暴露标签管理新增按钮"
        )
        XCTAssertFalse(
            app.buttons
                .matching(NSPredicate(format: "label CONTAINS %@", "新建标签"))
                .firstMatch.exists,
            "编辑器标签浮窗不应提供新建标签入口"
        )
    }

    func testEditorTagPickerSupportsMultipleSelectionWithoutClosing() {
        let app = XCUIApplication.heatMoment()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        let fab = app.buttons["新建时刻"]
        XCTAssertTrue(fab.waitForExistence(timeout: 10))
        fab.tap()

        let tagRow = app.buttons["editorTagRow"]
        XCTAssertTrue(tagRow.waitForExistence(timeout: 5))
        tagRow.tap()

        for tagName in ["工作", "生活", "健康"] {
            let option = app.buttons["tagOption-\(tagName)"]
            XCTAssertTrue(option.waitForExistence(timeout: 5), "\(tagName) 标签应存在")
            option.tap()
            XCTAssertTrue(option.waitForExistence(timeout: 2), "选择 \(tagName) 后标签浮窗不应关闭")
            XCTAssertEqual(option.value as? String, "已选中", "\(tagName) 标签应进入选中态")
        }

        dismissEditorFloatingPicker(app)
        XCTAssertTrue(tagRow.waitForExistence(timeout: 5))
    }

    func testEditorFloatingPickersRemainHittableAfterTextInput() {
        let app = XCUIApplication.heatMoment()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        let fab = app.buttons["新建时刻"]
        XCTAssertTrue(fab.waitForExistence(timeout: 10))
        fab.tap()

        let titleField = app.textFields["editorTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("键盘场景")

        let moodRow = app.buttons["editorMoodRow"]
        XCTAssertTrue(moodRow.waitForExistence(timeout: 5))
        moodRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["editorMoodPickerMenu"].exists)
        XCTAssertFalse(app.otherElements["PopoverDismissRegion"].exists)
        let happyOption = app.buttons["moodOption-1"]
        XCTAssertTrue(happyOption.waitForExistence(timeout: 5))
        XCTAssertTrue(happyOption.isHittable)
        happyOption.tap()

        titleField.tap()
        let tagRow = app.buttons["editorTagRow"]
        XCTAssertTrue(tagRow.waitForExistence(timeout: 5))
        tagRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["editorTagPickerMenu"].exists)
        XCTAssertFalse(app.otherElements["PopoverDismissRegion"].exists)
        let workTagOption = app.buttons["tagOption-工作"]
        XCTAssertTrue(workTagOption.waitForExistence(timeout: 5))
        XCTAssertTrue(workTagOption.isHittable)
        workTagOption.tap()
        dismissEditorFloatingPicker(app)
    }

    private func dismissEditorFloatingPicker(_ app: XCUIApplication) {
        let editorDismissRegion = app.otherElements["editorFloatingPickerDismissRegion"]
        XCTAssertTrue(editorDismissRegion.waitForExistence(timeout: 5))
        editorDismissRegion.tap()
    }

    private func dismissSystemPopover(_ app: XCUIApplication) {
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        XCTAssertTrue(dismissRegion.waitForExistence(timeout: 5))
        dismissRegion.tap()
    }
}
