import XCTest
@testable import Moodments

final class TimelineRailVisibilityTests: XCTestCase {
    func testFilteredEmptyStateDoesNotRenderRailRows() {
        let visibility = TimelineRailVisibility.resolve(
            visibleReadingUnitCount: 0,
            isFilteredEmpty: true
        )

        XCTAssertFalse(visibility.showsRailRows)
    }

    func testVisibleMomentsRenderRailRows() {
        let visibility = TimelineRailVisibility.resolve(
            visibleReadingUnitCount: 3,
            isFilteredEmpty: false
        )

        XCTAssertTrue(visibility.showsRailRows)
    }

    func testUnfilteredGuidedReadingUnitsRenderRailRows() {
        let visibility = TimelineRailVisibility.resolve(
            visibleReadingUnitCount: GuidedMoment.all.count,
            isFilteredEmpty: false
        )

        XCTAssertTrue(visibility.showsRailRows)
    }

    func testEmptyNonFilteredViewportDoesNotLeaveOrphanRail() {
        let visibility = TimelineRailVisibility.resolve(
            visibleReadingUnitCount: 0,
            isFilteredEmpty: false
        )

        XCTAssertFalse(visibility.showsRailRows)
    }
}
