import XCTest

final class BackupRestoreUITests: XCTestCase {
    func testBackupListShowsSystemMaintainedRecoveryPointAndPreview() {
        let app = launchLocalBackupApp(resetDisk: true, seedRecoveryPoint: true)
        openBackupRestore(app)

        XCTAssertTrue(app.staticTexts["backupRestoreRetentionText"].exists)
        XCTAssertTrue(app.staticTexts["backupRestoreSystemManagedText"].exists)

        let recoveryPoint = firstRecoveryPointRow(in: app)
        XCTAssertTrue(recoveryPoint.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["recoveryPointCreatedAtText"].exists)
        XCTAssertTrue(app.staticTexts["recoveryPointSummaryText"].exists)
        XCTAssertFalse(app.buttons["删除"].exists)
        XCTAssertFalse(app.buttons["彻底删除"].exists)

        recoveryPoint.tap()

        XCTAssertTrue(app.navigationBars["恢复备份"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["recoveryPointRestoreReplaceWarning"].exists)
        XCTAssertTrue(app.staticTexts["recoveryPointRestoreRestartInstruction"].exists)
        XCTAssertTrue(app.buttons["recoveryPointRestoreButton"].exists)
    }

    func testPreparedRestoreRunsOnNextLaunchAndShowsSuccess() {
        let runID = UUID().uuidString
        var app = launchLocalBackupApp(
            runID: runID,
            resetDisk: true,
            seedRecoveryPoint: true
        )
        openBackupRestore(app)

        let recoveryPoint = firstRecoveryPointRow(in: app)
        XCTAssertTrue(recoveryPoint.waitForExistence(timeout: 10))
        recoveryPoint.tap()

        let restoreButton = app.buttons["recoveryPointRestoreButton"]
        XCTAssertTrue(restoreButton.waitForExistence(timeout: 5))
        restoreButton.tap()

        let confirmation = app.alerts["恢复到这份备份？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["recoveryPointRestoreConfirmButton"].firstMatch.tap()

        XCTAssertTrue(app.otherElements["pendingLocalRestoreBlocker"].waitForExistence(timeout: 5))
        app.terminate()

        app = launchLocalBackupApp(runID: runID)
        let restored = app.alerts["本地备份恢复完成"]
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertTrue(
            restored.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "本机内容", "恢复前备份")
            ).firstMatch.exists
        )
        restored.buttons["好的"].tap()

        let restoredRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "备份里的时刻")
        ).firstMatch
        XCTAssertTrue(restoredRow.waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "当前未恢复时刻")
            ).firstMatch.exists
        )
    }

    private func launchLocalBackupApp(
        runID: String = UUID().uuidString,
        resetDisk: Bool = false,
        seedRecoveryPoint: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestLocalBackupRestore"]
        if resetDisk {
            app.launchArguments.append("-uiTestResetLocalBackupDisk")
        }
        if seedRecoveryPoint {
            app.launchArguments.append("-uiTestSeedLocalRecoveryPoint")
        }
        app.launchEnvironment["MOODMENTS_UI_TEST_LOCAL_BACKUP_RUN_ID"] = runID
        app.launch()
        return app
    }

    private func openBackupRestore(_ app: XCUIApplication) {
        let settings = app.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()

        let backupRestoreRow = app.buttons["settingsBackupRestoreRow"]
        XCTAssertTrue(backupRestoreRow.waitForExistence(timeout: 5))
        backupRestoreRow.tap()

        XCTAssertTrue(app.navigationBars["备份与恢复"].waitForExistence(timeout: 5))
    }

    private func firstRecoveryPointRow(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "recoveryPointRow-")
        ).firstMatch
    }
}
