import XCTest
@testable import Moodments

/// 篇数额度的释放时机验收（见 `docs/current/local-data-architecture.md` §3、
/// `docs/product-mental-model.md` 公理3「删除是生命周期」）：满额→`exceeded`；软删除后仍
/// `exceeded`（不释放，垃圾箱内记录仍计入额度）；只有彻底删除（`purge`）才释放额度。
final class MomentQuotaReleaseTests: XCTestCase {
    private var runtime: CanonicalLibraryRuntime!
    private let quotaService = QuotaService()

    override func setUpWithError() throws {
        runtime = try CanonicalLibraryRuntime.makeInMemoryForTests()
    }

    override func tearDown() {
        runtime = nil
    }

    func testSoftDeleteDoesNotReleaseQuotaOnlyPurgeDoes() async throws {
        var ids: [UUID] = []
        for index in 0..<Quota.freeMomentLimit {
            let id = try await runtime.repository.createMoment(
                title: "moment \(index)", bodyText: "", occurredAt: .now, mood: .normal
            )
            ids.append(id)
        }

        // 满额：第 11 篇应被拒绝。
        let fullCount = try await runtime.repository.totalMomentCount()
        XCTAssertEqual(fullCount, Quota.freeMomentLimit)
        XCTAssertEqual(
            quotaService.checkCanCreateMoment(currentMomentCount: fullCount),
            .exceeded(.moments)
        )

        // 软删除一篇进垃圾箱：额度计数不变，仍 exceeded（不释放，见 docs/current/local-data-architecture.md §3）。
        try await runtime.repository.softDeleteMoment(id: ids[0])
        let countAfterSoftDelete = try await runtime.repository.totalMomentCount()
        XCTAssertEqual(countAfterSoftDelete, Quota.freeMomentLimit)
        XCTAssertEqual(
            quotaService.checkCanCreateMoment(currentMomentCount: countAfterSoftDelete),
            .exceeded(.moments)
        )

        // 彻底删除同一篇：额度计数下降、恢复 allowed（释放，见 docs/current/local-data-architecture.md §3）。
        try await runtime.repository.purgeMoment(id: ids[0])
        let countAfterPurge = try await runtime.repository.totalMomentCount()
        XCTAssertEqual(countAfterPurge, Quota.freeMomentLimit - 1)
        XCTAssertEqual(
            quotaService.checkCanCreateMoment(currentMomentCount: countAfterPurge),
            .allowed
        )
    }
}
