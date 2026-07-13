import XCTest
@testable import HeatMoment

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

    func testTimelineBubbleStillUsesTheSameNodeAndSceneRailCoordinate() {
        let geometry = TimelineGeometry.standard

        XCTAssertEqual(geometry.railCenterXInViewport, geometry.nodeCenterXInViewport)
    }

    func testMomentPhotoRailWidthUsesClampedImageAspectRatio() {
        XCTAssertEqual(
            MomentPhotoRailLayout.itemWidth(for: CGSize(width: 300, height: 600)),
            MomentPhotoRailLayout.itemHeight * MomentPhotoRailLayout.minimumAspectRatio
        )
        XCTAssertEqual(
            MomentPhotoRailLayout.itemWidth(for: CGSize(width: 800, height: 400)),
            MomentPhotoRailLayout.itemHeight * MomentPhotoRailLayout.maximumAspectRatio
        )
        XCTAssertEqual(
            MomentPhotoRailLayout.itemWidth(for: CGSize(width: 120, height: 100)),
            MomentPhotoRailLayout.itemHeight * 1.2
        )
    }

    func testMomentPhotoRailInvalidImageSizeUsesFallbackWidth() {
        XCTAssertEqual(
            MomentPhotoRailLayout.itemWidth(for: .zero),
            MomentPhotoRailLayout.fallbackItemSize.width
        )
    }

    func testMomentPhotoRailDeleteBadgeUsesVisibleHitShapeSize() {
        XCTAssertEqual(MomentPhotoRailLayout.deleteBadgeDiameter, 24)
        XCTAssertEqual(MomentPhotoRailLayout.deleteBadgeOffset, 10)
        XCTAssertEqual(MomentPhotoRailLayout.deleteBadgeBorderWidth, 1)
    }

    func testThumbnailStripDefaultRemainsCompactTimelineLayout() {
        let strip = ThumbnailStripView(imageIDs: [])

        XCTAssertEqual(strip.displayMode, .scroll)
        XCTAssertFalse(strip.usesMomentPhotoRailLayout)
    }

    func testThumbnailStripCanOptIntoMomentPhotoRailLayout() {
        let imageID = UUID()
        let preferredSize = CGSize(width: 160, height: 168)
        let strip = ThumbnailStripView(
            imageIDs: [imageID],
            displayMode: .scroll,
            usesMomentPhotoRailLayout: true,
            preferredSizesByID: [imageID: preferredSize]
        )

        XCTAssertTrue(strip.usesMomentPhotoRailLayout)
        XCTAssertEqual(strip.preferredSizesByID[imageID], preferredSize)
    }
}
