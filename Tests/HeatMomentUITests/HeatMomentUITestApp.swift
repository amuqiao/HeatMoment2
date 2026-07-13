import XCTest

extension XCUIApplication {
    /// UI 测试统一入口：保证 Debug/Dev 本地 Pro 解锁在 XCUITest 中默认关闭。
    static func heatMoment() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HEATMOMENT_DISABLE_DEBUG_PRO_UNLOCK"] = "1"
        return app
    }
}
