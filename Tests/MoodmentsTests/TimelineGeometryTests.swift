import XCTest
@testable import Moodments

final class TimelineGeometryTests: XCTestCase {
    func testRailTopIsAboveFirstNodeWithBreathingSpaceBetweenThem() {
        let geometry = TimelineGeometry.standard
        let railTopY: CGFloat = 180
        let firstNodeCenterY = geometry.firstNodeCenterY(railTopY: railTopY)

        XCTAssertLessThan(railTopY, firstNodeCenterY)
        XCTAssertEqual(
            firstNodeCenterY - railTopY,
            geometry.firstNodeCenterYOffsetFromRailTop
        )
        XCTAssertGreaterThan(
            firstNodeCenterY - railTopY,
            geometry.nodeCenterY + geometry.nodeDiameter
        )
    }

    func testLeadInRemainsVisibleBeforeFirstReadingUnit() {
        let geometry = TimelineGeometry.standard

        XCTAssertGreaterThanOrEqual(geometry.railLeadInHeight, 48)
    }

    func testRailTopKeepsBreathingSpaceBelowExpandedTitle() {
        let geometry = TimelineGeometry.standard

        XCTAssertGreaterThanOrEqual(geometry.titleToRailTopSpacing, 8)
    }

    func testSceneRailStartsAboveFirstReadingUnitNode() {
        let geometry = TimelineGeometry.standard
        let measuredRailTopY: CGFloat = 248
        let firstNodeCenterY = geometry.firstNodeCenterY(railTopY: measuredRailTopY)

        XCTAssertLessThan(measuredRailTopY, firstNodeCenterY)
        XCTAssertGreaterThanOrEqual(
            firstNodeCenterY - measuredRailTopY,
            geometry.railLeadInHeight
        )
    }

    func testLeadInHeightPlacesFirstNodeAtConfiguredOffset() {
        let geometry = TimelineGeometry.standard

        XCTAssertEqual(
            geometry.railLeadInHeight + geometry.nodeCenterY,
            geometry.firstNodeCenterYOffsetFromRailTop
        )
    }

    func testViewportRailStartsAboveFirstNode() {
        let geometry = TimelineGeometry.standard
        let railTopY: CGFloat = 144

        XCTAssertLessThan(
            railTopY,
            geometry.firstNodeCenterY(railTopY: railTopY)
        )
        XCTAssertGreaterThanOrEqual(geometry.railBottomOvershoot, 200)
    }

    func testMeasuredRailBoundsUseTopAndBottomAnchors() {
        let bounds = TimelineRailSceneBounds(topY: 120, bottomY: 620)

        XCTAssertEqual(bounds.height, 500)
        XCTAssertEqual(bounds.midY, 370)
    }

    func testRailBoundsPreferenceCombinesTopAndBottomReports() {
        var preference = TimelineRailBoundsPreference(edge: .top, frame: CGRect(x: 0, y: 120, width: 1, height: 30))

        TimelineRailBoundsPreferenceKey.reduce(value: &preference) {
            TimelineRailBoundsPreference(edge: .bottom, frame: CGRect(x: 0, y: 700, width: 1, height: 80))
        }

        XCTAssertEqual(preference.bounds, TimelineRailSceneBounds(topY: 120, bottomY: 780))
    }

    func testSceneRailAndNodeShareTheSameViewportCoordinate() {
        let geometry = TimelineGeometry.standard

        XCTAssertEqual(
            geometry.railCenterXInViewport,
            geometry.nodeCenterXInViewport
        )
    }

    func testMovingTimelineHorizontalInsetMovesReadingUnitAndSceneRailTogether() {
        let base = TimelineGeometry.standard
        let moved = TimelineGeometry(listHorizontalInset: base.listHorizontalInset + 14)

        XCTAssertEqual(moved.rowInsets.leading, base.rowInsets.leading + 14)
        XCTAssertEqual(
            moved.nodeCenterXInViewport,
            base.nodeCenterXInViewport + 14
        )
        XCTAssertEqual(
            moved.railCenterXInViewport,
            base.railCenterXInViewport + 14
        )
    }

    func testChangingDateColumnWidthMovesNodeAndRailTogether() {
        let base = TimelineGeometry.standard
        let moved = TimelineGeometry(dateColumnWidth: base.dateColumnWidth + 10)

        XCTAssertEqual(
            moved.nodeCenterXInReadingUnit,
            base.nodeCenterXInReadingUnit + 10
        )
        XCTAssertEqual(
            moved.railCenterXInViewport,
            base.railCenterXInViewport + 10
        )
    }

    func testChangingInterColumnSpacingMovesNodeAndRailTogether() {
        let base = TimelineGeometry.standard
        let moved = TimelineGeometry(interColumnSpacing: base.interColumnSpacing + 8)

        XCTAssertEqual(
            moved.nodeCenterXInReadingUnit,
            base.nodeCenterXInReadingUnit + 8
        )
        XCTAssertEqual(
            moved.railCenterXInViewport,
            base.railCenterXInViewport + 8
        )
    }

    func testChangingNodeColumnWidthMovesNodeAndRailTogetherByHalfTheDelta() {
        let base = TimelineGeometry.standard
        let moved = TimelineGeometry(nodeColumnWidth: base.nodeColumnWidth + 10)

        XCTAssertEqual(
            moved.nodeCenterXInReadingUnit,
            base.nodeCenterXInReadingUnit + 5
        )
        XCTAssertEqual(
            moved.railCenterXInViewport,
            base.railCenterXInViewport + 5
        )
    }

}
