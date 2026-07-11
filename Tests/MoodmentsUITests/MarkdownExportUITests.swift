import XCTest

final class MarkdownExportUITests: XCTestCase {
    func testSettingsExportPageGeneratesMarkdownAndShowsShareLink() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedImageMoment"]
        app.launch()

        openExportPage(app)

        XCTAssertTrue(app.staticTexts["exportReadonlyText"].exists)

        let generateButton = app.buttons["exportGenerateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        generateButton.tap()

        XCTAssertTrue(app.otherElements["exportSuccessState"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["exportResultFormatText"].label.contains("Markdown"))
        XCTAssertTrue(app.staticTexts["exportFileNameText"].label.hasSuffix(".md"))
        XCTAssertTrue(app.staticTexts["exportAssetsSummaryText"].exists)
        XCTAssertTrue(app.buttons["exportShareLink"].exists)

        app.segmentedControls["exportFormatPicker"].buttons["PDF"].tap()
        XCTAssertFalse(app.otherElements["exportSuccessState"].exists)
    }

    func testSettingsExportPageGeneratesPDFAndShowsShareLink() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedImageMoment"]
        app.launch()

        openExportPage(app)

        let formatPicker = app.segmentedControls["exportFormatPicker"]
        XCTAssertTrue(formatPicker.waitForExistence(timeout: 5))
        formatPicker.buttons["PDF"].tap()

        let generateButton = app.buttons["exportGenerateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        generateButton.tap()

        XCTAssertTrue(app.otherElements["exportSuccessState"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["exportResultFormatText"].label.contains("PDF"))
        XCTAssertTrue(app.staticTexts["exportFileNameText"].label.hasSuffix(".pdf"))
        XCTAssertTrue(app.staticTexts["exportAssetsSummaryText"].exists)
        XCTAssertTrue(app.buttons["exportShareLink"].exists)
    }

    private func openExportPage(_ app: XCUIApplication) {
        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()

        let exportRow = app.buttons["settingsExportRow"]
        XCTAssertTrue(exportRow.waitForExistence(timeout: 5))
        exportRow.tap()

        XCTAssertTrue(app.navigationBars["导出"].waitForExistence(timeout: 5))
    }
}
