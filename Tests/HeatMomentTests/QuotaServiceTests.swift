import XCTest
@testable import HeatMoment

private struct MockEntitlementProvider: EntitlementProviding {
    let isPro: Bool
}

/// `QuotaService` 边界测试：见 `docs/product-mental-model.md` §2（15 篇 / 3 图 / 3 标签）。
final class QuotaServiceTests: XCTestCase {
    func testFifteenthMomentAllowedSixteenthBlocked() {
        let service = QuotaService(entitlementProvider: MockEntitlementProvider(isPro: false))
        // 已有 14 篇，新增第 15 篇：允许。
        XCTAssertEqual(service.checkCanCreateMoment(currentMomentCount: 14), .allowed)
        // 已有 15 篇，新增第 16 篇：拒绝。
        XCTAssertEqual(service.checkCanCreateMoment(currentMomentCount: 15), .exceeded(.moments))
    }

    func testFourthPhotoBlocked() {
        let service = QuotaService(entitlementProvider: MockEntitlementProvider(isPro: false))
        // 已有 2 张，追加第 3 张：允许。
        XCTAssertEqual(service.checkCanAddPhoto(currentPhotoCount: 2), .allowed)
        // 已有 3 张，追加第 4 张：拒绝。
        XCTAssertEqual(service.checkCanAddPhoto(currentPhotoCount: 3), .exceeded(.photosPerMoment))
    }

    func testFourthTagBlocked() {
        let service = QuotaService(entitlementProvider: MockEntitlementProvider(isPro: false))
        // 已有 2 个，新增第 3 个：允许。
        XCTAssertEqual(service.checkCanCreateTag(currentTagCount: 2), .allowed)
        // 已有 3 个，新增第 4 个：拒绝。
        XCTAssertEqual(service.checkCanCreateTag(currentTagCount: 3), .exceeded(.tags))
    }

    func testProUserIsUnlimited() {
        let service = QuotaService(entitlementProvider: MockEntitlementProvider(isPro: true))
        XCTAssertEqual(service.checkCanCreateMoment(currentMomentCount: 999), .allowed)
        XCTAssertEqual(service.checkCanAddPhoto(currentPhotoCount: 999), .allowed)
        XCTAssertEqual(service.checkCanCreateTag(currentTagCount: 999), .allowed)
    }
}
