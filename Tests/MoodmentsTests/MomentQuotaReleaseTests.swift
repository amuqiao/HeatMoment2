import XCTest
import SwiftData
@testable import Moodments

/// 篇数额度的释放时机验收（见 `docs/design/07-data-persistence.md` §3、
/// `docs/product-mental-model.md` 公理3「删除是生命周期」）：满额→`exceeded`；软删除后仍
/// `exceeded`（不释放，垃圾箱内记录仍计入额度）；只有彻底删除（`purge`）才释放额度。
final class MomentQuotaReleaseTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: MomentRepository!
    private let quotaService = QuotaService()

    override func setUpWithError() throws {
        container = try ModelContainerConfig.makeInMemoryContainer()
        repository = MomentRepository(modelContainer: container)
    }

    override func tearDown() {
        container = nil
        repository = nil
    }

    func testSoftDeleteDoesNotReleaseQuotaOnlyPurgeDoes() async throws {
        var ids: [UUID] = []
        for index in 0..<Quota.freeMomentLimit {
            let id = try await repository.createMoment(
                title: "moment \(index)", bodyText: "", occurredAt: .now, mood: .normal
            )
            ids.append(id)
        }

        // 满额：第 11 篇应被拒绝。
        let fullCount = try await repository.totalMomentCount()
        XCTAssertEqual(fullCount, Quota.freeMomentLimit)
        XCTAssertEqual(quotaService.checkCanCreateMoment(currentMomentCount: fullCount), .exceeded(.moments))

        // 软删除一篇进垃圾箱：额度计数不变，仍 exceeded（不释放，见 07 §3）。
        try await repository.softDelete(id: ids[0])
        let countAfterSoftDelete = try await repository.totalMomentCount()
        XCTAssertEqual(countAfterSoftDelete, Quota.freeMomentLimit)
        XCTAssertEqual(
            quotaService.checkCanCreateMoment(currentMomentCount: countAfterSoftDelete), .exceeded(.moments)
        )

        // 彻底删除同一篇：额度计数下降、恢复 allowed（释放，见 07 §3）。
        try await repository.purge(id: ids[0])
        let countAfterPurge = try await repository.totalMomentCount()
        XCTAssertEqual(countAfterPurge, Quota.freeMomentLimit - 1)
        XCTAssertEqual(quotaService.checkCanCreateMoment(currentMomentCount: countAfterPurge), .allowed)
    }
}
