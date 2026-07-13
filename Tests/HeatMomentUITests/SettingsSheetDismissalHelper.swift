import XCTest

extension XCTestCase {
    func dismissSettingsSheet(
        _ app: XCUIApplication,
        from rootAnchor: XCUIElement,
        expectedHomeButtonLabel: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            rootAnchor.waitForExistence(timeout: 5),
            "关闭设置 sheet 前应已回到设置根页锚点",
            file: file,
            line: line
        )

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.90))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(
            app.buttons[expectedHomeButtonLabel].waitForExistence(timeout: 5),
            "关闭设置 sheet 后应回到首页",
            file: file,
            line: line
        )
    }
}
