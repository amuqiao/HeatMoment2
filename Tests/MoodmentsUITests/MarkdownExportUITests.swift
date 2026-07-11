import XCTest

final class MarkdownExportUITests: XCTestCase {
    func testSettingsExportPageGeneratesMarkdownAndShowsShareLink() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedImageMoment"]
        app.launch()

        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()

        let exportRow = app.buttons["settingsExportRow"]
        XCTAssertTrue(exportRow.waitForExistence(timeout: 5))
        exportRow.tap()

        XCTAssertTrue(app.navigationBars["导出"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["markdownExportReadonlyText"].exists)

        let generateButton = app.buttons["markdownExportGenerateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        generateButton.tap()

        XCTAssertTrue(app.otherElements["markdownExportSuccessState"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["markdownExportFileNameText"].exists)
        XCTAssertTrue(app.staticTexts["markdownExportAssetsSummaryText"].exists)
        XCTAssertTrue(app.buttons["markdownExportShareLink"].exists)
    }
}
