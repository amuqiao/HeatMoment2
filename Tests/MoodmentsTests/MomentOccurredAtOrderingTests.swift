import XCTest
import SwiftData
@testable import Moodments

/// 以「发生时间」而非「创建时间」组织排序的专项测试（见 `docs/product-mental-model.md` 公理 8
/// 「以发生时间组织」，`docs/design/07-data-persistence.md` §3：排序/分页均以 `occurredAt`
/// 为主键，支持补记）。
final class MomentOccurredAtOrderingTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: MomentRepository!

    override func setUpWithError() throws {
        container = try ModelContainerConfig.makeInMemoryContainer()
        repository = MomentRepository(modelContainer: container)
    }

    override func tearDown() {
        container = nil
        repository = nil
    }

    /// 先创建 `occurredAt=now` 的记录，再创建 `occurredAt=now-1天` 的补记记录：尽管补记记录
    /// 的「创建顺序」更晚，排序仍必须按 `occurredAt`（发生时间）倒序，补记记录应排在后面，
    /// 而不是因为后创建而排到前面。
    func testBackfilledMomentSortsByOccurredAtNotCreatedAt() async throws {
        let now = Date.now
        let recentID = try await repository.createMoment(
            title: "recent", bodyText: "", occurredAt: now, mood: .happy
        )
        let backfilledID = try await repository.createMoment(
            title: "backfilled", bodyText: "", occurredAt: now.addingTimeInterval(-86400), mood: .sad
        )

        let page = try await repository.fetchPage(offset: 0, limit: 10)

        XCTAssertEqual(page.map(\.id), [recentID, backfilledID])
    }

    /// 修改一条记录的 `occurredAt` 应重排时间轴顺序（补记语义，见公理 8）。
    func testEditingOccurredAtReorders() async throws {
        let now = Date.now
        let firstID = try await repository.createMoment(
            title: "first", bodyText: "", occurredAt: now, mood: .happy
        )
        let secondID = try await repository.createMoment(
            title: "second", bodyText: "", occurredAt: now.addingTimeInterval(-3600), mood: .sad
        )

        let before = try await repository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(before.map(\.id), [firstID, secondID])

        // 把 second 的发生时间改到最新，应翻转到最前。
        try await repository.updateMoment(id: secondID, occurredAt: now.addingTimeInterval(3600))

        let after = try await repository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(after.map(\.id), [secondID, firstID])
    }
}
