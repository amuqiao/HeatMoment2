import XCTest
@testable import Moodments

/// 以「发生时间」而非「创建时间」组织排序的专项测试（见 `docs/product-mental-model.md` 公理 8
/// 「以发生时间组织」，`docs/current/local-data-architecture.md` §3：排序/分页均以 `occurredAt`
/// 为主键，支持补记）。
final class MomentOccurredAtOrderingTests: XCTestCase {
    private var runtime: CanonicalLibraryRuntime!

    override func setUpWithError() throws {
        runtime = try CanonicalLibraryRuntime.makeInMemoryForTests()
    }

    override func tearDown() {
        runtime = nil
    }

    /// 先创建 `occurredAt=now` 的记录，再创建 `occurredAt=now-1天` 的补记记录：尽管补记记录
    /// 的「创建顺序」更晚，排序仍必须按 `occurredAt`（发生时间）倒序，补记记录应排在后面，
    /// 而不是因为后创建而排到前面。
    func testBackfilledMomentSortsByOccurredAtNotCreatedAt() async throws {
        let now = Date.now
        let recentID = try await runtime.repository.createMoment(
            title: "recent", bodyText: "", occurredAt: now, mood: .happy
        )
        let backfilledID = try await runtime.repository.createMoment(
            title: "backfilled",
            bodyText: "",
            occurredAt: now.addingTimeInterval(-86400),
            mood: .sad
        )

        let page = try await runtime.repository.fetchPage(offset: 0, limit: 10)

        XCTAssertEqual(page.map(\.id), [recentID, backfilledID])
    }

    /// 修改一条记录的 `occurredAt` 应重排时间轴顺序（补记语义，见公理 8）。
    func testEditingOccurredAtReorders() async throws {
        let now = Date.now
        let firstID = try await runtime.repository.createMoment(
            title: "first", bodyText: "", occurredAt: now, mood: .happy
        )
        let secondID = try await runtime.repository.createMoment(
            title: "second", bodyText: "", occurredAt: now.addingTimeInterval(-3600), mood: .sad
        )

        let before = try await runtime.repository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(before.map(\.id), [firstID, secondID])

        // 把 second 的发生时间改到最新，应翻转到最前。
        try await runtime.repository.updateMoment(
            id: secondID,
            occurredAt: now.addingTimeInterval(3600)
        )

        let after = try await runtime.repository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(after.map(\.id), [secondID, firstID])
    }
}
