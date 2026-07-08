import XCTest

/// P0 首页视觉取证入口：生成首页、热力图、筛选标记、左滑和亮色截图。
///
/// 本用例的断言只负责确保目标 UI 状态可达；截图会同时写到
/// `/private/tmp/heatmoment-p0-visual`，供 `docs/plans/implementation-plan.md`
/// 的 P0 视觉验收审计使用。
final class P0VisualAuditCaptureUITests: XCTestCase {
    private let outputDirectory = URL(
        fileURLWithPath: "/private/tmp/heatmoment-p0-visual",
        isDirectory: true
    )

    override func setUpWithError() throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
    }

    @MainActor
    func testCaptureP0VisualAuditStates() {
        captureDarkHomeHeatmapAndMarkers()
        captureSwipeDeleteState()
        captureLightHome()
    }

    @MainActor
    private func captureDarkHomeHeatmapAndMarkers() {
        let app = launchSeededTimeline()
        waitForSeededTimeline(app)
        capture(app, name: "01-home-dark")

        app.buttons["年度心情热力图"].tap()
        XCTAssertTrue(app.buttons["heatmapCloseButton"].waitForExistence(timeout: 5))
        capture(app, name: "02-heatmap-expanded-dark")

        let dayCell = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "heatmapDayCell-"))
            .firstMatch
        XCTAssertTrue(dayCell.waitForExistence(timeout: 5))
        dayCell.tap()
        capture(app, name: "03-heatmap-day-selected-dark")

        app.buttons["heatmapCloseButton"].tap()
        collapseTitleAndOpenFilter(app)

        let workTagOption = app.buttons["filterTagOption-工作"]
        XCTAssertTrue(workTagOption.waitForExistence(timeout: 5))
        workTagOption.tap()

        let doneButton = app.buttons["filterDoneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()
        capture(app, name: "04-filter-and-locate-markers-dark")

        app.terminate()
    }

    @MainActor
    private func captureSwipeDeleteState() {
        let app = launchSeededTimeline()
        waitForSeededTimeline(app)

        let row = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "《测试时刻 1》"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()

        XCTAssertTrue(app.buttons["timelineSwipeDeleteButton"].waitForExistence(timeout: 5))
        capture(app, name: "05-swipe-delete-revealed-dark")

        app.terminate()
    }

    @MainActor
    private func captureLightHome() {
        let app = launchSeededTimeline()
        waitForSeededTimeline(app)

        app.buttons["设置"].tap()
        let appearanceRow = app.buttons["settingsAppearanceRow"]
        XCTAssertTrue(appearanceRow.waitForExistence(timeout: 5))
        appearanceRow.tap()

        let lightOption = app.buttons["appearanceModeOption-light"]
        XCTAssertTrue(lightOption.waitForExistence(timeout: 5))
        lightOption.tap()

        if app.navigationBars.buttons.element(boundBy: 0).exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(app.buttons["settingsAppearanceRow"].waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.90))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(app.buttons["新建时刻"].waitForExistence(timeout: 5))
        capture(app, name: "06-home-light")

        app.terminate()
    }

    @MainActor
    private func launchSeededTimeline() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSeedMoments"]
        app.launch()
        return app
    }

    @MainActor
    private func waitForSeededTimeline(_ app: XCUIApplication) {
        let row = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "测试时刻 1"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
    }

    @MainActor
    private func collapseTitleAndOpenFilter(_ app: XCUIApplication) {
        for _ in 0..<4 {
            app.swipeUp()
        }
        let collapsedTitle = app.buttons["timelineCollapsedTitleButton"]
        XCTAssertTrue(collapsedTitle.waitForExistence(timeout: 5))
        collapsedTitle.tap()
        XCTAssertTrue(app.buttons["filterMoodOption-1"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = app.screenshot().image
        guard let data = screenshot.pngData() else {
            XCTFail("无法编码截图 \(name)")
            return
        }
        let url = outputDirectory.appendingPathComponent("\(name).png")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            XCTFail("无法写入截图 \(url.path): \(error)")
        }
    }
}
