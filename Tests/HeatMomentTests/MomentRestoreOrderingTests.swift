import XCTest
@testable import HeatMoment

/// 恢复后重排位置验收（见 `docs/product-mental-model.md` 公理8「以发生时间组织」、
/// 公理3「删除是生命周期」——恢复 = 带着原发生时间/心情/标签/内容回归）：
/// 软删中间一条记录再恢复，应回到按 `occurredAt` 倒序的原有位置，而不是排到列表两端。
final class MomentRestoreOrderingTests: XCTestCase {
    private var runtime: CanonicalLibraryRuntime!

    override func setUpWithError() throws {
        runtime = try CanonicalLibraryRuntime.makeInMemoryForTests()
    }

    override func tearDown() {
        runtime = nil
    }

    func testRestoringMiddleMomentReturnsToOriginalOccurredAtPosition() async throws {
        let now = Date.now
        let newestID = try await runtime.repository.createMoment(
            title: "newest", bodyText: "", occurredAt: now, mood: .happy
        )
        let middleID = try await runtime.repository.createMoment(
            title: "middle", bodyText: "", occurredAt: now.addingTimeInterval(-1000), mood: .sad
        )
        let oldestID = try await runtime.repository.createMoment(
            title: "oldest", bodyText: "", occurredAt: now.addingTimeInterval(-2000), mood: .normal
        )

        try await runtime.repository.softDeleteMoment(id: middleID)
        let pageWithoutMiddle = try await runtime.repository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(pageWithoutMiddle.map(\.id), [newestID, oldestID])

        try await runtime.repository.restoreMoment(id: middleID)
        let pageAfterRestore = try await runtime.repository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(
            pageAfterRestore.map(\.id), [newestID, middleID, oldestID],
            "恢复后应回到原 occurredAt 倒序位置（居中），而非排到列表两端"
        )
    }

    /// 恢复带回原发生时间/心情/内容（见公理3「恢复 = 这条记录重新属于我的时间轴」）。
    func testRestoredMomentKeepsOriginalFields() async throws {
        let occurredAt = Date(timeIntervalSince1970: 0)
        let id = try await runtime.repository.createMoment(
            title: "标题", bodyText: "正文", occurredAt: occurredAt, mood: .angry
        )
        try await runtime.repository.softDeleteMoment(id: id)
        try await runtime.repository.restoreMoment(id: id)

        let page = try await runtime.repository.fetchPage(offset: 0, limit: 10)
        let restored = try XCTUnwrap(page.first { $0.id == id })
        XCTAssertEqual(restored.title, "标题")
        XCTAssertEqual(restored.bodyText, "正文")
        XCTAssertEqual(restored.occurredAt, occurredAt)
        XCTAssertEqual(restored.mood, .angry)
        XCTAssertFalse(restored.isDeleted)
        XCTAssertNil(restored.deletedAt)
    }
}
