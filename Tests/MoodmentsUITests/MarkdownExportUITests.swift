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

    func testSettingsExportPageShowsRangeAndPhotoControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedImageMoment"]
        app.launch()

        openExportPage(app)

        let scopePicker = app.segmentedControls["exportScopePicker"]
        XCTAssertTrue(scopePicker.waitForExistence(timeout: 5))
        XCTAssertTrue(scopePicker.buttons["全部"].exists)
        XCTAssertTrue(scopePicker.buttons["日期范围"].exists)
        XCTAssertTrue(app.switches["exportIncludePhotosToggle"].exists)

        scopePicker.buttons["日期范围"].tap()

        XCTAssertTrue(exportControlExists(app, identifier: "exportStartDatePicker"))
        XCTAssertTrue(exportControlExists(app, identifier: "exportEndDatePicker"))
        XCTAssertTrue(app.buttons["exportGenerateButton"].isEnabled)
    }

    func testSettingsExportPageRetriesDateBoundsLoadFailure() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedImageMoment", "-uiTestExportDateBoundsFailOnce"]
        app.launch()

        openExportPage(app)

        let failureState = app.otherElements["exportFailureState"]
        XCTAssertTrue(failureState.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["exportFailureMessage"].label.contains("导出数据读取失败"))
        XCTAssertFalse(app.staticTexts["exportValidationText"].exists)

        app.buttons["exportRetryButton"].tap()

        XCTAssertTrue(app.segmentedControls["exportScopePicker"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["exportFailureState"].exists)
        XCTAssertTrue(app.buttons["exportGenerateButton"].isEnabled)
    }

    func testSettingsExportPageShowsFailureAndRetryForInvalidPDFImage() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestExportForcePDFFailure"]
        app.launch()

        openExportPage(app)

        let formatPicker = app.segmentedControls["exportFormatPicker"]
        XCTAssertTrue(formatPicker.waitForExistence(timeout: 5))
        formatPicker.buttons["PDF"].tap()

        let generateButton = app.buttons["exportGenerateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        generateButton.tap()

        let failureState = app.otherElements["exportFailureState"]
        XCTAssertTrue(failureState.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["exportFailureMessage"].label.contains("PDF 导出失败"))
        XCTAssertTrue(app.buttons["exportRetryButton"].exists)
        XCTAssertFalse(app.otherElements["exportSuccessState"].exists)
        let firstAttemptValue = failureState.value as? String ?? ""

        app.buttons["exportRetryButton"].tap()
        XCTAssertTrue(
            waitForFailureRetry(failureState, previousValue: firstAttemptValue, timeout: 5)
        )
        XCTAssertTrue(failureState.waitForExistence(timeout: 10))
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

    private func waitForFailureRetry(
        _ element: XCUIElement,
        previousValue: String,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "value != %@", previousValue)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func exportControlExists(_ app: XCUIApplication, identifier: String) -> Bool {
        app.datePickers[identifier].exists
            || app.otherElements[identifier].exists
            || app.buttons[identifier].exists
    }
}
