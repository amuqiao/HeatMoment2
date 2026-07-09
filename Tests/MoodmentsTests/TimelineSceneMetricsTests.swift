import XCTest
@testable import Moodments

final class TimelineSceneMetricsTests: XCTestCase {
    func testResponsiveSceneUsesStandardDesignAnchorsOnBaseWidth() {
        let scene = TimelineSceneMetrics.responsive(for: 390)
        let geometry = scene.layout.geometry

        XCTAssertEqual(geometry.listHorizontalInset, 16)
        XCTAssertEqual(geometry.dateColumnWidth, 38)
        XCTAssertEqual(geometry.interColumnSpacing, 6)
        XCTAssertEqual(geometry.nodeColumnWidth, 24)
        XCTAssertEqual(geometry.railCenterXInViewport, 72)
        XCTAssertEqual(geometry.bubbleLeadingXInReadingUnit, 74)
        XCTAssertEqual(geometry.rowInsets.leading, 16)
        XCTAssertEqual(scene.layout.viewport.restingRailTopY, 50)
        XCTAssertEqual(scene.layout.home.topChromeHorizontalPadding, 18)
        XCTAssertEqual(scene.layout.home.fabVisualProtectionInset, 8)
        XCTAssertEqual(scene.layout.home.bottomActionClearance, 94)
    }

    func testResponsiveSceneKeepsTimelineUsableOnNarrowPhones() {
        let scene = TimelineSceneMetrics.responsive(for: 320)
        let geometry = scene.layout.geometry

        XCTAssertEqual(geometry.listHorizontalInset, 14)
        XCTAssertEqual(geometry.dateColumnWidth, 33.5)
        XCTAssertEqual(geometry.interColumnSpacing, 5.5)
        XCTAssertEqual(geometry.nodeColumnWidth, 21)
        XCTAssertEqual(geometry.railCenterXInViewport, 63.5)
        XCTAssertLessThan(geometry.rowInsets.leading, 16)
        XCTAssertLessThan(geometry.bubbleLeadingXInReadingUnit, 66)
    }

    func testResponsiveSceneKeepsTimelineUsableOnWidePhones() {
        let scene = TimelineSceneMetrics.responsive(for: 430)
        let geometry = scene.layout.geometry

        XCTAssertEqual(geometry.listHorizontalInset, 17.5)
        XCTAssertEqual(geometry.dateColumnWidth, 42)
        XCTAssertEqual(geometry.interColumnSpacing, 6.5)
        XCTAssertEqual(geometry.nodeColumnWidth, 26.5)
        XCTAssertEqual(geometry.railCenterXInViewport, 79.25)
        XCTAssertGreaterThan(geometry.bubbleLeadingXInReadingUnit, 81)
    }

    func testResponsiveSceneSeparatesVisualStyleReplacementFromTimelineAnchors() {
        var style = TimelineSceneStyle.standard
        style.node.innerDiameterRatio = 0.65
        style.bubble.cornerRadius = 24
        style.chromeIcon.settingsSize = CGSize(width: 36, height: 36)

        let scene = TimelineSceneMetrics.responsive(for: 390, baseStyle: style)
        let geometry = scene.layout.geometry

        XCTAssertEqual(geometry.dateColumnWidth, 38)
        XCTAssertEqual(geometry.nodeDiameter, 20)
        XCTAssertEqual(geometry.nodeColumnWidth, 24)
        XCTAssertEqual(geometry.nodeCenterXInReadingUnit, 56)
        XCTAssertEqual(scene.style.node.innerDiameterRatio, 0.65)
        XCTAssertEqual(scene.style.bubble.cornerRadius, 24)
        XCTAssertEqual(scene.style.chromeIcon.settingsSize, CGSize(width: 36, height: 36))
    }

    func testBubbleTailKeepsBreathingSpaceFromMoodNode() {
        let geometry = TimelineSceneMetrics.responsive(for: 390).layout.geometry
        let nodeRightEdge = geometry.nodeCenterXInReadingUnit + geometry.nodeDiameter / 2
        let tailTipX = geometry.bubbleLeadingXInReadingUnit + geometry.bubbleTailHorizontalOffset

        XCTAssertEqual(tailTipX - nodeRightEdge, 5)
    }

    func testBubbleTailBreathingSpaceScalesAcrossPhoneWidths() {
        assertBubbleTailGap(width: 320, gap: 4.5)
        assertBubbleTailGap(width: 390, gap: 5)
        assertBubbleTailGap(width: 430, gap: 5.5)
    }

    func testNodeColumnWidthTokenIsClampedByNodeDiameter() {
        let geometry = TimelineSceneMetrics.responsive(
            for: 390,
            layoutTokens: TimelineLayoutTokens(
                nodeColumnWidth: 12,
                nodeDiameter: 20
            )
        ).layout.geometry

        XCTAssertEqual(geometry.nodeColumnWidth, 22)
        XCTAssertEqual(
            geometry.nodeColumnWidth,
            geometry.nodeDiameter + 2
        )
    }

    func testNodeToBubbleTailGapTokenDrivesTailBreathingSpace() {
        let geometry = TimelineSceneMetrics.responsive(
            for: 390,
            layoutTokens: TimelineLayoutTokens(nodeToBubbleTailGap: 9)
        ).layout.geometry
        let nodeRightEdge = geometry.nodeCenterXInReadingUnit + geometry.nodeDiameter / 2
        let tailTipX = geometry.bubbleLeadingXInReadingUnit + geometry.bubbleTailHorizontalOffset

        XCTAssertEqual(tailTipX - nodeRightEdge, 9)
    }

    func testResponsiveSceneScalesDateStampSpacing() {
        var style = TimelineSceneStyle.standard
        style.dateStamp.monthSpacing = 5
        style.dateStamp.verticalSpacing = 5

        let narrow = TimelineSceneMetrics.responsive(for: 320, baseStyle: style)
        let base = TimelineSceneMetrics.responsive(for: 390, baseStyle: style)

        XCTAssertEqual(base.style.dateStamp.monthSpacing, 5)
        XCTAssertEqual(base.style.dateStamp.verticalSpacing, 5)
        XCTAssertEqual(narrow.style.dateStamp.monthSpacing, 4.5)
        XCTAssertEqual(narrow.style.dateStamp.verticalSpacing, 4.5)
    }

    private func assertBubbleTailGap(width: CGFloat, gap: CGFloat) {
        let geometry = TimelineSceneMetrics.responsive(for: width).layout.geometry
        let nodeRightEdge = geometry.nodeCenterXInReadingUnit + geometry.nodeDiameter / 2
        let tailOffsetX = geometry.bubbleTailHorizontalOffset
        let tailTipX = geometry.bubbleLeadingXInReadingUnit + tailOffsetX

        XCTAssertEqual(tailTipX - nodeRightEdge, gap)
    }
}
