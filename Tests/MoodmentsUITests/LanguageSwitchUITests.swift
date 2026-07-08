import XCTest

/// 语言切换验收（见 `docs/design/12-quality-assurance.md` §12.2、`docs/design/04-screen-specs.md`
/// §4.11「语言」行、阶段7计划决策4）：设置页「语言」子页三选一，切换后**无需重启**（不需要
/// 杀掉/重新打开 App 进程）即让核心流程文案随之改变。
///
/// **即时性范围说明**（见 `MoodmentsApp.body` 内 `.environment(\.locale, ...)` 注释、真机/
/// 模拟器实测确认）：普通 `Text`/`Button` 字面量在已挂载页面上会正确即时刷新（本文件断言的
/// 设置根页「语言」行、时间轴 FAB「新建时刻」均属此类，且**不需要用户手动来回导航**，
/// 只是从设置根页切到「语言」子页再切回来）；但 `.navigationTitle(_:)` 桥接到 UIKit
/// `UINavigationItem.title` 存在已知的「已挂载导航栈不随环境重算刷新」滞后，故本文件**不**对
/// 导航栏标题文案做断言（该滞后已在 `MoodmentsApp` 头部注释登记为已知例外，不影响「无需重启」
/// 这一核心契约——用户仍可继续操作，只是导航栏标题需要下一次重新呈现该任务卡片才会刷新）。
///
/// **默认态验证**（隐含）：本文件之外的全部既有 UI 测试套件均按中文可见文案精确断言且从不
/// 触碰语言设置——它们持续全绿本身就是「冷启动默认语言 = 简体中文，不受宿主机/模拟器系统区域
/// 影响」这一契约（`LanguagePreference` 默认 `.zhHans`，见其头部说明）的最强验证；本文件只
/// 额外覆盖「切换到 English 后核心文案随之改变」与「可切换回简体中文」两条路径。
final class LanguageSwitchUITests: XCTestCase {
    /// 切到 English：无需重启，「设置」根页「语言」行与时间轴 FAB「新建时刻」均随之
    /// 改为英文，且切换过程中未离开过设置任务卡片栈（不是靠重新呈现刷新的）。
    func testSwitchingToEnglishUpdatesCoreTextImmediately() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 10), "默认语言应为简体中文")

        openLanguageSettings(app)

        let englishOption = app.buttons["languageOption-english"]
        XCTAssertTrue(englishOption.waitForExistence(timeout: 5))
        englishOption.tap()
        XCTAssertTrue(englishOption.isSelected, "点选后应立即变为选中态")

        // 返回设置根页（同一个任务卡片栈内 pop，不是重新呈现）：「语言」行应已即时变为英文。
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let languageRow = app.buttons["settingsLanguageRow"]
        XCTAssertTrue(languageRow.waitForExistence(timeout: 5))
        XCTAssertTrue(
            languageRow.label.contains("Language"),
            "切换语言应立即生效，无需重启/无需重新呈现设置"
        )
        XCTAssertFalse(app.buttons["Close"].exists, "设置根页不应再提供显式关闭按钮")
        dismissSettingsSheet(
            app,
            from: app.buttons["settingsLanguageRow"],
            expectedHomeButtonLabel: "New Moment"
        )

        // 回到时间轴：FAB 无障碍标签（核心新建入口）也应已切换为英文。
        XCTAssertTrue(app.buttons["New Moment"].waitForExistence(timeout: 5))
    }

    /// 切到 English 后再切回简体中文：核心文案应恢复为中文（双向验证，非单向不可逆开关）。
    func testSwitchingBackToChineseRestoresOriginalText() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 10))

        openLanguageSettings(app)
        app.buttons["languageOption-english"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["settingsLanguageRow"].label.contains("Language"))

        // 再次进入语言子页切回简体中文（`settingsLanguageRow` 此刻应已是英文态设置页的一部分，
        // 用 identifier 定位不受当前展示语言影响）。
        app.buttons["settingsLanguageRow"].tap()
        let zhHansOption = app.buttons["languageOption-zhHans"]
        XCTAssertTrue(zhHansOption.waitForExistence(timeout: 5))
        zhHansOption.tap()
        XCTAssertTrue(zhHansOption.isSelected)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let languageRow = app.buttons["settingsLanguageRow"]
        XCTAssertTrue(languageRow.waitForExistence(timeout: 5))
        XCTAssertTrue(languageRow.label.contains("语言"), "切回简体中文应立即生效")
        XCTAssertFalse(app.buttons["关闭"].exists, "设置根页不应再提供显式关闭按钮")
        dismissSettingsSheet(
            app,
            from: app.buttons["settingsLanguageRow"],
            expectedHomeButtonLabel: "新建时刻"
        )

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 5))
    }

    // MARK: - Helpers

    private func openLanguageSettings(_ app: XCUIApplication) {
        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        let languageRow = app.buttons["settingsLanguageRow"]
        XCTAssertTrue(languageRow.waitForExistence(timeout: 5))
        languageRow.tap()

        XCTAssertTrue(app.navigationBars["语言"].waitForExistence(timeout: 5))
    }

}
