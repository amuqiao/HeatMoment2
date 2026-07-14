import XCTest

final class BackupRestoreUITests: XCTestCase {
    @MainActor
    func testBackupRestorePageShowsMinimalCompleteBackupWorkflow() {
        let app = launchLocalBackupApp(resetDisk: true, seedLocalData: true)
        openBackupRestore(app)

        XCTAssertTrue(app.otherElements["backupSummarySection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["backupPackageSection"].exists)
        XCTAssertTrue(app.staticTexts["当前内容"].exists)
        XCTAssertTrue(app.staticTexts["完整备份"].exists)
        let operationPicker = app.segmentedControls["backupPackageOperationPicker"]
        XCTAssertTrue(operationPicker.waitForExistence(timeout: 5))
        XCTAssertTrue(operationPicker.buttons["导出备份"].exists)
        XCTAssertTrue(operationPicker.buttons["导入还原"].exists)

        let primaryButton = app.buttons["backupPackagePrimaryButton"]
        XCTAssertTrue(primaryButton.exists)
        XCTAssertEqual(primaryButton.label, "导出备份")
        XCTAssertFalse(app.buttons["导入备份"].exists)

        operationPicker.buttons["导入还原"].tap()
        XCTAssertTrue(waitForLabel(primaryButton, "导入备份", timeout: 5))
        XCTAssertFalse(app.staticTexts["backupPackageExplanationText"].exists)
        XCTAssertFalse(app.otherElements["backupSafetySection"].exists)
        XCTAssertFalse(app.staticTexts["恢复机制"].exists)
        XCTAssertFalse(app.staticTexts["已生成备份包"].exists)
        XCTAssertFalse(firstRecoveryPointRow(in: app).exists)
        XCTAssertFalse(app.buttons["recoveryPointRestoreButton"].exists)
    }

    @MainActor
    private func launchLocalBackupApp(
        runID: String = UUID().uuidString,
        resetDisk: Bool = false,
        seedLocalData: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication.heatMoment()
        app.launchArguments = ["-uiTestLocalBackupRestore"]
        if resetDisk {
            app.launchArguments.append("-uiTestResetLocalBackupDisk")
        }
        if seedLocalData {
            app.launchArguments.append("-uiTestSeedLocalRecoveryPoint")
        }
        app.launchEnvironment["HEATMOMENT_UI_TEST_LOCAL_BACKUP_RUN_ID"] = runID
        app.launch()
        return app
    }

    @MainActor
    private func openBackupRestore(_ app: XCUIApplication) {
        let settings = app.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()

        let backupRestoreRow = app.buttons["settingsBackupRestoreRow"]
        XCTAssertTrue(backupRestoreRow.waitForExistence(timeout: 5))
        backupRestoreRow.tap()

        XCTAssertTrue(app.navigationBars["备份/还原"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func firstRecoveryPointRow(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "recoveryPointRow-")
        )
        .firstMatch
    }

    @MainActor
    private func waitForLabel(
        _ element: XCUIElement,
        _ label: String,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
