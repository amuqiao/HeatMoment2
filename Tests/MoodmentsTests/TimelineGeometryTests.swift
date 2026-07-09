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
            geometry.nodeDiameter
        )
        XCTAssertGreaterThanOrEqual(
            firstNodeCenterY - geometry.nodeDiameter / 2 - railTopY,
            20
        )
    }

    func testLeadInRemainsVisibleBeforeFirstReadingUnit() {
        let geometry = TimelineGeometry.standard

        XCTAssertGreaterThanOrEqual(geometry.railLeadInHeight, 4)
        XCTAssertLessThanOrEqual(geometry.railLeadInHeight, 10)
    }

    func testViewportLayoutOwnsBreathingSpaceBelowExpandedTitle() {
        let geometry = TimelineGeometry.standard
        let layout = TimelineViewportLayout.standard
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 760),
            scrollOffsetY: 0,
            sceneLayout: sceneLayout(viewport: layout, geometry: geometry)
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
            sceneLayout: sceneLayout(viewport: layout, geometry: geometry)
        )

        XCTAssertEqual(layout.expandedTitleTopPadding, 0)
        XCTAssertEqual(metrics.railTopY, 50)
        XCTAssertEqual(metrics.restingFirstNodeCenterY, 80)
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
            titleToRailTopSpacing: 16,
            railBottomOvershoot: 280
        )
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 620),
            scrollOffsetY: 0,
            sceneLayout: sceneLayout(viewport: layout, geometry: geometry)
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
