import XCTest
@testable import HeatMoment

final class TimelineLayoutResolverTests: XCTestCase {
    func testRailTopToFirstMomentTopGapDirectlyControlsLeadIn() {
        let scene = TimelineSceneMetrics.responsive(
            for: 390,
            layoutTokens: TimelineLayoutTokens(railTopToFirstMomentTopGap: 2)
        )
        let viewport = scene.layout.viewport

        XCTAssertEqual(viewport.railTopToFirstMomentTopGap, 2)
        XCTAssertEqual(viewport.restingFirstReadingUnitTopY, 52)
        XCTAssertEqual(scene.layout.geometry.nodeCenterY, 24)
    }

    func testNodeCenterYDoesNotOwnFirstMomentContainerGap() {
        let scene = TimelineSceneMetrics.responsive(
            for: 390,
            layoutTokens: TimelineLayoutTokens(
                nodeCenterYInMoment: 30,
                railTopToFirstMomentTopGap: 6
            )
        )
        let geometry = scene.layout.geometry
        let viewport = scene.layout.viewport

        XCTAssertEqual(viewport.railTopToFirstMomentTopGap, 6)
        XCTAssertEqual(geometry.nodeCenterY, 30)
        XCTAssertEqual(viewport.restingFirstReadingUnitTopY, 56)
        XCTAssertEqual(geometry.nodeTopPadding, 20)
    }

    func testTitleToRailTopGapMovesRailWithoutChangingMomentInternalGeometry() {
        let scene = TimelineSceneMetrics.responsive(
            for: 390,
            layoutTokens: TimelineLayoutTokens(
                railTopToFirstMomentTopGap: 6,
                titleToRailTopGap: 2
            )
        )
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 760),
            scrollOffsetY: 0,
            sceneLayout: scene.layout
        )

        XCTAssertEqual(scene.layout.viewport.restingRailTopY, 46)
        XCTAssertEqual(scene.layout.viewport.railTopToFirstMomentTopGap, 6)
        XCTAssertEqual(scene.layout.geometry.nodeCenterY, 24)
        XCTAssertEqual(metrics.restingFirstNodeCenterY, 76)
    }

    func testViewportMetricsDerivesFirstNodePositionFromSceneAndMomentGeometry() {
        let scene = TimelineSceneMetrics.responsive(
            for: 390,
            layoutTokens: TimelineLayoutTokens(
                nodeCenterYInMoment: 30,
                railTopToFirstMomentTopGap: 2
            )
        )
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 760),
            scrollOffsetY: 0,
            sceneLayout: scene.layout
        )

        XCTAssertEqual(scene.layout.viewport.restingFirstReadingUnitTopY, 52)
        XCTAssertEqual(metrics.restingFirstNodeCenterY, 82)
    }

    func testMovingTimelineHorizontalInsetTokenMovesReadingUnitAndSceneRailTogether() {
        let base = TimelineGeometry.standard
        let moved = TimelineSceneMetrics.responsive(
            for: 390,
            layoutTokens: TimelineLayoutTokens(
                listHorizontalInset: base.listHorizontalInset + 14
            )
        ).layout.geometry

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

    func testChangingDateColumnWidthTokenMovesNodeAndRailTogether() {
        let base = TimelineGeometry.standard
        let moved = TimelineSceneMetrics.responsive(
            for: 390,
            layoutTokens: TimelineLayoutTokens(
                dateColumnWidth: base.dateColumnWidth + 10
            )
        ).layout.geometry

        XCTAssertEqual(
            moved.nodeCenterXInReadingUnit,
            base.nodeCenterXInReadingUnit + 10
        )
        XCTAssertEqual(
            moved.railCenterXInViewport,
            base.railCenterXInViewport + 10
        )
    }

    func testChangingColumnSpacingTokenMovesNodeAndRailTogether() {
        let base = TimelineGeometry.standard
        let moved = TimelineSceneMetrics.responsive(
            for: 390,
            layoutTokens: TimelineLayoutTokens(
                columnSpacing: base.interColumnSpacing + 8
            )
        ).layout.geometry

        XCTAssertEqual(
            moved.nodeCenterXInReadingUnit,
            base.nodeCenterXInReadingUnit + 8
        )
        XCTAssertEqual(
            moved.railCenterXInViewport,
            base.railCenterXInViewport + 8
        )
    }

    func testChangingNodeColumnWidthTokenMovesNodeAndRailTogetherByHalfTheDelta() {
        let base = TimelineGeometry.standard
        let moved = TimelineSceneMetrics.responsive(
            for: 390,
            layoutTokens: TimelineLayoutTokens(
                nodeColumnWidth: base.nodeColumnWidth + 10
            )
        ).layout.geometry

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
