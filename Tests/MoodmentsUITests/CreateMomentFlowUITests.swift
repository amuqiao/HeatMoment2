import XCTest

/// 新建时刻完整流程验收（见 `docs/design/03-user-flows.md` §3.1、
/// `docs/plans/implementation-plan.md` 阶段 3 验收：情绪→标签→日期→标题→保存→出现在时间轴）。
///
/// 标签选择用首启默认预置的标签（工作/生活/健康，见 `DefaultTagSeeder`），不新建标签
/// （见阶段 3 计划决策4）。日期/时间就近浮窗的验证只做「打开→控件存在→点浮窗外部收起」，
/// 不深入操作系统 `DatePicker` 内部的具体日期格（图形日历控件的可访问性标签依赖当前系统
/// 区域/月份布局，逐日选择在 `XCUITest` 中天然脆弱，此处按「跑通就近浮窗打开/收起」验收，
/// 已在完成报告中说明该取舍）。
final class CreateMomentFlowUITests: XCTestCase {
    func testFullCreateFlowAppendsBubbleToTimeline() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        let fab = app.buttons["新建时刻"]
        XCTAssertTrue(fab.waitForExistence(timeout: 10))
        fab.tap()

        // 情绪：打开就近浮窗，选「开心」（Mood.happy.rawValue == 1）。
        let moodRow = app.buttons["editorMoodRow"]
        XCTAssertTrue(moodRow.waitForExistence(timeout: 5))
        moodRow.tap()
        let happyOption = app.buttons["moodOption-1"]
        XCTAssertTrue(happyOption.waitForExistence(timeout: 5))
        happyOption.tap()

        // 标签：打开就近浮窗，选预置标签「工作」（不新建，见类型头部说明）。
        let tagRow = app.buttons["editorTagRow"]
        XCTAssertTrue(tagRow.waitForExistence(timeout: 5))
        tagRow.tap()
        let workTagOption = app.buttons["tagOption-工作"]
        XCTAssertTrue(workTagOption.waitForExistence(timeout: 5))
        workTagOption.tap()
        dismissAnyPopover(app)

        // 日期：打开就近浮窗，确认日历控件出现，再点外部收起（见类型头部关于日期格自动化的说明）。
        let dateChip = app.buttons["editorDateChip"]
        XCTAssertTrue(dateChip.waitForExistence(timeout: 5))
        dateChip.tap()
        XCTAssertTrue(app.datePickers["editorDatePicker"].waitForExistence(timeout: 5))
        dismissAnyPopover(app)

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

    /// 点击浮窗外部收起当前就近浮窗（popover 语义，见 04-screen-specs.md §4.5/§4.6/§4.8）：
    /// 直接命中系统为 `.popover` 自动生成的 `PopoverDismissRegion` 无障碍元素（覆盖浮窗之外的
    /// 整个可交互区域），比对一个猜测的屏幕坐标做 `tap()` 更可靠——曾实测坐标 tap 未必落在
    /// 该区域内、导致浮窗未真正收起。
    private func dismissAnyPopover(_ app: XCUIApplication) {
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        XCTAssertTrue(dismissRegion.waitForExistence(timeout: 5))
        dismissRegion.tap()
    }
}
