import XCTest

final class BackupRestoreUITests: XCTestCase {
    @MainActor
    func testBackupRestorePageShowsMinimalCompleteBackupWorkflow() {
        let app = launchLocalBackupApp(resetDisk: true, seedLocalData: true)
        openBackupRestore(app)

        XCTAssertTrue(app.otherElements["backupSummarySection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["backupPackageSection"].exists)
        XCTAssertTrue(app.staticTexts["当前内容"].exists)
        XCTAssertTrue(app.staticTexts["backupCurrentSummaryRecordMetric"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["backupCurrentSummaryRecordMetric"].label, "记录 2")
        XCTAssertEqual(app.staticTexts["backupCurrentSummaryUsedTagMetric"].label, "使用标签 0")
        XCTAssertEqual(app.staticTexts["backupCurrentSummaryPhotoMetric"].label, "照片 0")
        XCTAssertTrue(app.staticTexts["backupCurrentSummaryTimestamp"].label.hasPrefix("读取于 "))
        XCTAssertTrue(app.staticTexts["上次导出"].exists)
        XCTAssertEqual(app.staticTexts["backupLastExportSummaryPlaceholder"].label, "从未导出")
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
        XCTAssertFalse(app.otherElements["backupImportPreviewSection"].exists)
        XCTAssertFalse(app.buttons["backupPackagePrepareImportButton"].exists)
        XCTAssertFalse(firstRecoveryPointRow(in: app).exists)
        XCTAssertFalse(app.buttons["recoveryPointRestoreButton"].exists)
    }

    @MainActor
    func testCompletedBackupExportUpdatesLastExportedSummary() {
        let app = launchLocalBackupApp(
            resetDisk: true,
            seedLocalData: true,
            autoCompleteBackupShare: true
        )
        openBackupRestore(app)

        XCTAssertTrue(app.staticTexts["上次导出"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["backupLastExportSummaryPlaceholder"].exists)

        app.buttons["backupPackagePrimaryButton"].tap()

        XCTAssertTrue(
            waitForNonExistence(app.staticTexts["backupLastExportSummaryPlaceholder"], timeout: 8)
        )
        XCTAssertTrue(app.staticTexts["backupLastExportSummaryRecordMetric"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["backupLastExportSummaryRecordMetric"].label, "记录 2")
        XCTAssertEqual(app.staticTexts["backupLastExportSummaryUsedTagMetric"].label, "使用标签 0")
        XCTAssertEqual(app.staticTexts["backupLastExportSummaryPhotoMetric"].label, "照片 0")
        let exportedAtLabel = app.staticTexts["backupLastExportSummaryTimestamp"]
        XCTAssertTrue(exportedAtLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(
            exportedAtLabel.label.range(
                of: #"^导出于 \d{4}年\d{1,2}月\d{1,2}日 \d{2}:\d{2}$"#,
                options: .regularExpression
            ) != nil
        )
    }

    @MainActor
    private func launchLocalBackupApp(
        runID: String = UUID().uuidString,
        resetDisk: Bool = false,
        seedLocalData: Bool = false,
        autoCompleteBackupShare: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication.heatMoment()
        app.launchArguments = ["-uiTestLocalBackupRestore"]
        if resetDisk {
            app.launchArguments.append("-uiTestResetLocalBackupDisk")
        }
        if seedLocalData {
            app.launchArguments.append("-uiTestSeedLocalRecoveryPoint")
        }
        if autoCompleteBackupShare {
            app.launchArguments.append("-uiTestBackupPackageShareAutoComplete")
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

    @MainActor
    private func waitForNonExistence(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
