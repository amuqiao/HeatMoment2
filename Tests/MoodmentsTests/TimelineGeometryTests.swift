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

        XCTAssertGreaterThanOrEqual(geometry.railLeadInHeight, 24)
        XCTAssertLessThanOrEqual(geometry.railLeadInHeight, 36)
    }

    func testViewportLayoutOwnsBreathingSpaceBelowExpandedTitle() {
        let geometry = TimelineGeometry.standard
        let layout = TimelineViewportLayout.standard
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 760),
            scrollOffsetY: 0,
            layout: layout,
            firstNodeCenterYOffsetFromRailTop: geometry.firstNodeCenterYOffsetFromRailTop
        )

        XCTAssertGreaterThanOrEqual(layout.titleToRailTopSpacing, 6)
        XCTAssertEqual(
            metrics.railTopY,
            layout.expandedTitleSlotBottomY + layout.titleToRailTopSpacing
        )
        XCTAssertLessThan(metrics.railTopY, metrics.restingFirstNodeCenterY)
    }

    func testDefaultViewportLayoutKeepsExpandedTitleAndFirstNodeCompact() {
        let geometry = TimelineGeometry.standard
        let layout = TimelineViewportLayout.standard
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 760),
            scrollOffsetY: 0,
            layout: layout,
            firstNodeCenterYOffsetFromRailTop: geometry.firstNodeCenterYOffsetFromRailTop
        )

        XCTAssertEqual(layout.expandedTitleTopPadding, 0)
        XCTAssertEqual(metrics.railTopY, 56)
        XCTAssertEqual(metrics.restingFirstNodeCenterY, 116)
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
    }

    func testViewportMetricsProducesVisibleRailBoundsAtRest() {
        let geometry = TimelineGeometry.standard
        let layout = TimelineViewportLayout.standard
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 760),
            scrollOffsetY: 0,
            layout: layout,
            firstNodeCenterYOffsetFromRailTop: geometry.firstNodeCenterYOffsetFromRailTop
        )

        XCTAssertEqual(metrics.railBounds.topY, layout.restingRailTopY)
        XCTAssertEqual(metrics.railBounds.bottomY, 760 + layout.railBottomOvershoot)
        XCTAssertGreaterThan(metrics.railBounds.height, 0)
    }

    func testHomeBottomClearanceIsOwnedByFabLayout() {
        let layout = TimelineHomeLayout.standard

        XCTAssertEqual(FABButtonMetrics.diameter, 64)
        XCTAssertEqual(layout.fabDiameter, FABButtonMetrics.diameter)
        XCTAssertEqual(layout.fabBottomPadding, 24)
        XCTAssertEqual(layout.bottomActionClearance, 96)
    }

    func testEditorUsesCompactInsetsWithoutChangingGlobalTaskPageInsets() {
        XCTAssertEqual(TaskSurfaceMetrics.pageVerticalInset, 20)
        XCTAssertEqual(TaskSurfaceMetrics.pageBottomInset, 56)
        XCTAssertEqual(EditorLayout.chromeActionSlotWidth, 64)
        XCTAssertEqual(EditorLayout.contentTopInset, 10)
        XCTAssertEqual(EditorLayout.contentGroupSpacing, 20)
    }

    func testViewportRailBoundsDoNotDependOnListRowPreferences() {
        let geometry = TimelineGeometry.standard
        let layout = TimelineViewportLayout.standard
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 620),
            scrollOffsetY: 0,
            layout: layout,
            firstNodeCenterYOffsetFromRailTop: geometry.firstNodeCenterYOffsetFromRailTop
        )

        let bounds = metrics.railBounds

        XCTAssertEqual(bounds.topY, layout.restingRailTopY)
        XCTAssertEqual(bounds.bottomY, 620 + layout.railBottomOvershoot)
        XCTAssertLessThan(bounds.topY, metrics.restingFirstNodeCenterY)
    }

    func testViewportRailDoesNotMoveDownWhenPullingPastTop() {
        let geometry = TimelineGeometry.standard
        let layout = TimelineViewportLayout.standard
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 620),
            scrollOffsetY: -40,
            layout: layout,
            firstNodeCenterYOffsetFromRailTop: geometry.firstNodeCenterYOffsetFromRailTop
        )

        XCTAssertEqual(metrics.railTopY, layout.restingRailTopY)
    }

    func testViewportRailMovesUpWithContentWhenScrollingForward() {
        let geometry = TimelineGeometry.standard
        let layout = TimelineViewportLayout.standard
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 620),
            scrollOffsetY: 44,
            layout: layout,
            firstNodeCenterYOffsetFromRailTop: geometry.firstNodeCenterYOffsetFromRailTop
        )

        XCTAssertEqual(metrics.railTopY, layout.restingRailTopY - 44)
    }

    func testViewportLayoutMovesRailTopThroughNamedSceneSlot() {
        let geometry = TimelineGeometry.standard
        let layout = TimelineViewportLayout(
            expandedTitleSlotBottomY: 80,
            expandedTitleTopPadding: 2,
            titleToRailTopSpacing: 16,
            railBottomOvershoot: 280
        )
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 620),
            scrollOffsetY: 0,
            layout: layout,
            firstNodeCenterYOffsetFromRailTop: geometry.firstNodeCenterYOffsetFromRailTop
        )

        XCTAssertEqual(layout.restingRailTopY, 96)
        XCTAssertEqual(layout.expandedTitleTopPadding, 2)
        XCTAssertEqual(metrics.railTopY, 96)
        XCTAssertEqual(metrics.railBottomY, 900)
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
