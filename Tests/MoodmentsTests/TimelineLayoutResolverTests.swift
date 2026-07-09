import XCTest
@testable import Moodments

final class TimelineLayoutResolverTests: XCTestCase {
    func testFirstMomentTopBreathingDirectlyControlsLeadIn() {
        let scene = TimelineSceneMetrics.responsive(
            for: 390,
            layoutTokens: TimelineLayoutTokens(firstMomentTopBreathing: 2)
        )
        let geometry = scene.layout.geometry

        XCTAssertEqual(geometry.railLeadInHeight, 2)
        XCTAssertEqual(geometry.nodeCenterY, 24)
        XCTAssertEqual(geometry.firstNodeCenterYOffsetFromRailTop, 26)
    }

    func testNodeCenterYDoesNotOwnFirstMomentBreathing() {
        let scene = TimelineSceneMetrics.responsive(
            for: 390,
            layoutTokens: TimelineLayoutTokens(
                nodeCenterYInRow: 30,
                firstMomentTopBreathing: 6
            )
        )
        let geometry = scene.layout.geometry

        XCTAssertEqual(geometry.railLeadInHeight, 6)
        XCTAssertEqual(geometry.nodeCenterY, 30)
        XCTAssertEqual(geometry.firstNodeCenterYOffsetFromRailTop, 36)
        XCTAssertEqual(geometry.nodeTopPadding, 20)
    }

    func testViewportMetricsDerivesFirstNodePositionFromResolvedGeometry() {
        let scene = TimelineSceneMetrics.responsive(
            for: 390,
            layoutTokens: TimelineLayoutTokens(
                nodeCenterYInRow: 30,
                firstMomentTopBreathing: 2
            )
        )
        let metrics = TimelineViewportMetrics(
            viewportSize: CGSize(width: 430, height: 760),
            scrollOffsetY: 0,
            sceneLayout: scene.layout
        )

        XCTAssertEqual(scene.layout.geometry.firstNodeCenterYOffsetFromRailTop, 32)
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
