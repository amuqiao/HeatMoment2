import XCTest
@testable import Moodments

final class TimelineGeometryTests: XCTestCase {
    func testRailTopIsAboveFirstNodeWithBreathingSpaceBetweenThem() {
        let geometry = TimelineGeometry.standard
        let layout = TimelineViewportLayout.standard
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 760),
            scrollOffsetY: 0,
            sceneLayout: sceneLayout(viewport: layout, geometry: geometry)
        )

        XCTAssertLessThan(metrics.railTopY, metrics.restingFirstReadingUnitTopY)
        XCTAssertLessThan(metrics.restingFirstReadingUnitTopY, metrics.restingFirstNodeCenterY)
        XCTAssertEqual(
            metrics.restingFirstReadingUnitTopY - metrics.railTopY,
            layout.railTopToFirstMomentTopGap
        )
        XCTAssertEqual(
            metrics.restingFirstNodeCenterY - metrics.restingFirstReadingUnitTopY,
            geometry.nodeCenterY
        )
        XCTAssertGreaterThan(
            metrics.restingFirstNodeCenterY - metrics.railTopY,
            geometry.nodeDiameter
        )
    }

    func testRailTopToFirstMomentTopGapRemainsCompactByDefault() {
        let layout = TimelineViewportLayout.standard

        XCTAssertGreaterThanOrEqual(layout.railTopToFirstMomentTopGap, 0)
        XCTAssertLessThanOrEqual(layout.railTopToFirstMomentTopGap, 10)
    }

    func testViewportLayoutOwnsBreathingSpaceBelowExpandedTitle() {
        let geometry = TimelineGeometry.standard
        let layout = TimelineViewportLayout.standard
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 760),
            scrollOffsetY: 0,
            sceneLayout: sceneLayout(viewport: layout, geometry: geometry)
        )

        XCTAssertGreaterThanOrEqual(layout.titleToRailTopGap, 6)
        XCTAssertEqual(
            metrics.railTopY,
            layout.expandedTitleSlotBottomY + layout.titleToRailTopGap
        )
        XCTAssertLessThan(metrics.railTopY, metrics.restingFirstNodeCenterY)
    }

    func testDefaultViewportLayoutKeepsExpandedTitleAndFirstNodeCompact() {
        let geometry = TimelineGeometry.standard
        let layout = TimelineViewportLayout.standard
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 760),
            scrollOffsetY: 0,
            sceneLayout: sceneLayout(viewport: layout, geometry: geometry)
        )

        XCTAssertEqual(layout.expandedTitleTopPadding, 0)
        XCTAssertEqual(layout.expandedTitleContentSlotHeight, 44)
        XCTAssertEqual(metrics.railTopY, 50)
        XCTAssertEqual(metrics.restingFirstReadingUnitTopY, 52)
        XCTAssertEqual(metrics.restingFirstNodeCenterY, 76)
    }

    func testSceneRailStartsAboveFirstReadingUnitNode() {
        let geometry = TimelineGeometry.standard
        let layout = TimelineViewportLayout.standard
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 620),
            scrollOffsetY: 0,
            sceneLayout: sceneLayout(viewport: layout, geometry: geometry)
        )

        XCTAssertLessThan(metrics.railTopY, metrics.restingFirstNodeCenterY)
        XCTAssertEqual(
            metrics.restingFirstNodeCenterY,
            layout.restingFirstReadingUnitTopY + geometry.nodeCenterY
        )
    }

    func testRailTopToFirstMomentTopGapPlacesFirstNodeAtConfiguredOffset() {
        let layout = TimelineViewportLayout.standard

        XCTAssertEqual(
            layout.restingRailTopY + layout.railTopToFirstMomentTopGap,
            layout.restingFirstReadingUnitTopY
        )
    }

    func testViewportRailStartsAboveFirstNode() {
        let geometry = TimelineGeometry.standard
        let layout = TimelineViewportLayout.standard
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 620),
            scrollOffsetY: 0,
            sceneLayout: sceneLayout(viewport: layout, geometry: geometry)
        )

        XCTAssertLessThan(
            metrics.railTopY,
            metrics.restingFirstNodeCenterY
        )
    }

    func testViewportMetricsProducesVisibleRailBoundsAtRest() {
        let geometry = TimelineGeometry.standard
        let layout = TimelineViewportLayout.standard
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 760),
            scrollOffsetY: 0,
            sceneLayout: sceneLayout(viewport: layout, geometry: geometry)
        )

        XCTAssertEqual(metrics.railBounds.topY, layout.restingRailTopY)
        XCTAssertEqual(metrics.railBounds.bottomY, 760 + layout.railBottomOvershoot)
        XCTAssertGreaterThan(metrics.railBounds.height, 0)
    }

    func testHomeBottomClearanceIsOwnedByFabLayout() {
        let layout = TimelineHomeLayout.standard

        XCTAssertEqual(layout.fabDiameter, 64)
        XCTAssertEqual(layout.fabBottomPadding, 18)
        XCTAssertEqual(layout.fabSafetyGap, 4)
        XCTAssertEqual(layout.fabVisualProtectionInset, 8)
        XCTAssertEqual(layout.bottomActionClearance, 94)
    }

    func testTimelineBottomTailKeepsFabClearanceInsideScrollableContent() {
        let viewport = TimelineViewportLayout.standard
        let home = TimelineHomeLayout.standard

        XCTAssertEqual(viewport.railBottomOvershoot, 48)
        XCTAssertEqual(viewport.bottomTailClearance(protecting: home.bottomActionClearance), 94)
    }

    func testViewportRailBoundsDoNotDependOnListRowPreferences() {
        let geometry = TimelineGeometry.standard
        let layout = TimelineViewportLayout.standard
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 620),
            scrollOffsetY: 0,
            sceneLayout: sceneLayout(viewport: layout, geometry: geometry)
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
            sceneLayout: sceneLayout(viewport: layout, geometry: geometry)
        )

        XCTAssertEqual(metrics.railTopY, layout.restingRailTopY)
    }

    func testViewportRailMovesUpWithContentWhenScrollingForward() {
        let geometry = TimelineGeometry.standard
        let layout = TimelineViewportLayout.standard
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 620),
            scrollOffsetY: 44,
            sceneLayout: sceneLayout(viewport: layout, geometry: geometry)
        )

        XCTAssertEqual(metrics.railTopY, layout.restingRailTopY - 44)
    }

    func testViewportLayoutMovesRailTopThroughNamedSceneSlot() {
        let geometry = TimelineGeometry.standard
        let layout = TimelineViewportLayout(
            expandedTitleSlotBottomY: 80,
            expandedTitleTopPadding: 2,
            titleToRailTopGap: 16,
            railTopToFirstMomentTopGap: 10,
            railBottomOvershoot: 280
        )
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 620),
            scrollOffsetY: 0,
            sceneLayout: sceneLayout(viewport: layout, geometry: geometry)
        )

        XCTAssertEqual(layout.restingRailTopY, 96)
        XCTAssertEqual(layout.expandedTitleTopPadding, 2)
        XCTAssertEqual(layout.expandedTitleContentSlotHeight, 78)
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

    private func sceneLayout(
        viewport: TimelineViewportLayout = .standard,
        geometry: TimelineGeometry = .standard
    ) -> TimelineSceneLayout {
        TimelineSceneLayout(
            home: .standard,
            viewport: viewport,
            geometry: geometry
        )
    }
}
