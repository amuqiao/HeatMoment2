import XCTest
@testable import Moodments

final class MomentCardLayoutTests: XCTestCase {
    func testContentKindEnumeratesSupportedVisibleStates() {
        XCTAssertEqual(
            MomentCardContentKind(title: "标题", bodyText: "", hasImages: false),
            .titleOnly
        )
        XCTAssertEqual(
            MomentCardContentKind(title: "", bodyText: "正文", hasImages: false),
            .bodyOnly
        )
        XCTAssertEqual(
            MomentCardContentKind(title: "标题", bodyText: "正文", hasImages: false),
            .titleAndBody
        )
        XCTAssertEqual(
            MomentCardContentKind(title: "标题", bodyText: "", hasImages: true),
            .textWithImages
        )
        XCTAssertEqual(
            MomentCardContentKind(title: "", bodyText: "", hasImages: true),
            .imagesOnly
        )
    }

    func testImageSectionHeightIsModeDrivenNotImageCountDriven() {
        XCTAssertEqual(
            MomentCardLayout.imageSectionHeight(for: .scroll),
            MomentCardLayout.thumbnailSize.height
        )
        XCTAssertEqual(
            MomentCardLayout.imageSectionHeight(for: .carousel),
            MomentCardLayout.carouselHeight
        )
    }

    func testTimelineImageGalleryOwnsMediaGestures() {
        XCTAssertTrue(
            MomentCardLayout.timelineImageGalleryAllowsHitTesting,
            "首页气泡图片区是媒体交互区，图片上的横向滑动不能触发行级删除"
        )
    }

    func testTimelineBubbleStillUsesTheSameNodeAndRailCoordinate() {
        let geometry = TimelineGeometry.standard

        XCTAssertEqual(geometry.railCenterXInViewport, geometry.nodeCenterXInListRow)
    }
}
