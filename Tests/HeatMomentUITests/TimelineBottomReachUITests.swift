import XCTest

/// 首页时间轴底部可达性验收：底部 FAB 是 overlay，不应把时间轴 viewport 截短到看不到尾部内容。
final class TimelineBottomReachUITests: XCTestCase {
    func testSeededTimelineBottomRowCanScrollAboveFAB() {
        let app = XCUIApplication.heatMoment()
        app.launchArguments = ["-uiTestSeedMoments"]
        app.launch()

        let firstRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "测试时刻 1"))
            .firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10))

        let lastRow = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "测试时刻 12"))
            .firstMatch
        for _ in 0..<10 where !lastRow.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(lastRow.waitForExistence(timeout: 5), "上滑到底后应能看到最后一条时间轴记录")

        let fab = app.buttons["新建时刻"]
        XCTAssertTrue(fab.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(
            lastRow.frame.maxY,
            fab.frame.minY + 2,
            "最后一条时间轴记录应能滚到 FAB 上方，不应被底部浮层遮挡"
        )
    }
}
