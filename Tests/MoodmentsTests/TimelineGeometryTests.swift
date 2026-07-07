import XCTest
@testable import Moodments

final class TimelineGeometryTests: XCTestCase {
    func testRailTopIsAboveFirstNodeWithBreathingSpaceBetweenThem() {
        let geometry = TimelineGeometry.standard
        let railTopY: CGFloat = 0
        let firstNodeCenterY = railTopY + geometry.firstNodeCenterYOffsetFromRailTop

        XCTAssertLessThan(railTopY, firstNodeCenterY)
        XCTAssertEqual(
            firstNodeCenterY - railTopY,
            geometry.railLeadInHeight + geometry.nodeCenterY
        )
        XCTAssertGreaterThan(
            firstNodeCenterY - railTopY,
            geometry.nodeCenterY + geometry.nodeDiameter
        )
    }

    func testLeadInRemainsVisibleBeforeFirstReadingUnit() {
        let geometry = TimelineGeometry.standard

        XCTAssertGreaterThanOrEqual(geometry.railLeadInHeight, 44)
    }
}
