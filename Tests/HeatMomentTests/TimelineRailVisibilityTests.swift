import XCTest
@testable import HeatMoment

final class TimelineRailVisibilityTests: XCTestCase {
    func testFilteredEmptyStateDoesNotRenderSceneRail() {
        let visibility = TimelineRailVisibility.resolve(
            visibleReadingUnitCount: 0,
            isFilteredEmpty: true
        )

        XCTAssertFalse(visibility.showsRail)
    }

    func testVisibleMomentsRenderSceneRail() {
        let visibility = TimelineRailVisibility.resolve(
            visibleReadingUnitCount: 3,
            isFilteredEmpty: false
        )

        XCTAssertTrue(visibility.showsRail)
    }

    func testEmptyNonFilteredViewportDoesNotLeaveOrphanRail() {
        let visibility = TimelineRailVisibility.resolve(
            visibleReadingUnitCount: 0,
            isFilteredEmpty: false
        )

        XCTAssertFalse(visibility.showsRail)
    }
}
