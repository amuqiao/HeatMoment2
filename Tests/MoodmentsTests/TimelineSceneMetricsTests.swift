import XCTest
@testable import Moodments

final class TimelineSceneMetricsTests: XCTestCase {
    func testResponsiveSceneUsesStandardDesignAnchorsOnBaseWidth() {
        let scene = TimelineSceneMetrics.responsive(for: 390)
        let geometry = scene.layout.geometry

        XCTAssertEqual(geometry.listHorizontalInset, 16)
        XCTAssertEqual(geometry.dateColumnWidth, 38)
        XCTAssertEqual(geometry.interColumnSpacing, 4)
        XCTAssertEqual(geometry.nodeColumnWidth, 22)
        XCTAssertEqual(geometry.railCenterXInViewport, 69)
        XCTAssertEqual(geometry.rowInsets.leading, 16)
        XCTAssertEqual(scene.layout.viewport.restingRailTopY, 58)
        XCTAssertEqual(scene.layout.home.topChromeHorizontalPadding, 18)
    }

    func testResponsiveSceneKeepsTimelineUsableOnNarrowPhones() {
        let scene = TimelineSceneMetrics.responsive(for: 320)
        let geometry = scene.layout.geometry

        XCTAssertEqual(geometry.listHorizontalInset, 14)
        XCTAssertEqual(geometry.dateColumnWidth, 33.5)
        XCTAssertEqual(geometry.interColumnSpacing, 3.5)
        XCTAssertEqual(geometry.nodeColumnWidth, 20)
        XCTAssertEqual(geometry.railCenterXInViewport, 61)
        XCTAssertLessThan(geometry.rowInsets.leading, 16)
        XCTAssertLessThan(geometry.bubbleLeadingXInReadingUnit, 62)
    }

    func testResponsiveSceneKeepsTimelineUsableOnWidePhones() {
        let scene = TimelineSceneMetrics.responsive(for: 430)
        let geometry = scene.layout.geometry

        XCTAssertEqual(geometry.listHorizontalInset, 17.5)
        XCTAssertEqual(geometry.dateColumnWidth, 42)
        XCTAssertEqual(geometry.interColumnSpacing, 4.5)
        XCTAssertEqual(geometry.nodeColumnWidth, 24.5)
        XCTAssertEqual(geometry.railCenterXInViewport, 76.25)
        XCTAssertGreaterThan(geometry.bubbleLeadingXInReadingUnit, 70)
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
        XCTAssertEqual(geometry.nodeColumnWidth, 22)
        XCTAssertEqual(geometry.nodeCenterXInReadingUnit, 53)
        XCTAssertEqual(scene.style.node.innerDiameterRatio, 0.65)
        XCTAssertEqual(scene.style.bubble.cornerRadius, 24)
        XCTAssertEqual(scene.style.chromeIcon.settingsSize, CGSize(width: 36, height: 36))
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
}
