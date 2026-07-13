import XCTest

final class BackupRestoreUITests: XCTestCase {
    @MainActor
    func testBackupRestorePageShowsCompletePackageWorkflow() {
        let app = launchLocalBackupApp(resetDisk: true, seedLocalData: true)
        openBackupRestore(app)

        XCTAssertTrue(app.otherElements["backupSummarySection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["backupPackageSection"].exists)
        XCTAssertTrue(app.staticTexts["backupPackageExplanationText"].exists)
        XCTAssertTrue(app.otherElements["backupSafetySection"].exists)
        XCTAssertTrue(app.buttons["导出完整备份"].exists)
        XCTAssertTrue(app.buttons["导入完整备份"].exists)
        XCTAssertFalse(firstRecoveryPointRow(in: app).exists)
        XCTAssertFalse(app.buttons["recoveryPointRestoreButton"].exists)
    }

    @MainActor
    func testExportCompleteBackupPackageShowsShareLink() {
        let app = launchLocalBackupApp(resetDisk: true, seedLocalData: true)
        openBackupRestore(app)

        let exportButton = app.buttons["导出完整备份"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()

        XCTAssertTrue(app.otherElements["backupExportResultSection"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["backupPackageShareLink"].exists)
        XCTAssertTrue(app.staticTexts["已生成备份包"].exists)
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

        XCTAssertTrue(app.navigationBars["备份与恢复"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func firstRecoveryPointRow(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "recoveryPointRow-")
        )
        .firstMatch
    }
}
