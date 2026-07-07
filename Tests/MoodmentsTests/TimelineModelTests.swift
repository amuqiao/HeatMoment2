import XCTest
@testable import Moodments

/// `TimelineModel.discardFilterTag` 验收（见阶段6计划决策5、
/// `docs/plans/implementation-plan.md` 阶段6 §8「筛选中标签被删除后的陈旧标记」）：
/// 标签删除后清理 `activeFilter` 中的陈旧 id，移除后两个维度都为空则整体置 `nil`，
/// 不误触 `mood` 维度；`heatmapFocusDate`（定位）与本操作完全独立（公理2）。
@MainActor
final class TimelineModelTests: XCTestCase {
    func testDiscardFilterTagRemovesOnlyThatTagFromMultiTagFilter() {
        let model = TimelineModel()
        let keepID = UUID()
        let removeID = UUID()
        model.activeFilter = FilterCondition(tagIDs: [keepID, removeID])

        model.discardFilterTag(removeID)

        XCTAssertEqual(model.activeFilter?.tagIDs, [keepID])
    }

    /// 移除后标签与心情都为空 → `activeFilter` 整体置 `nil`（回到「无筛选」态）。
    func testDiscardFilterTagClearsActiveFilterWhenBothDimensionsEmpty() {
        let model = TimelineModel()
        let tagID = UUID()
        model.activeFilter = FilterCondition(tagIDs: [tagID])

        model.discardFilterTag(tagID)

        XCTAssertNil(model.activeFilter)
    }

    /// 移除标签后若仍选中心情，`activeFilter` 应保留（只清标签维度，不误触心情维度）。
    func testDiscardFilterTagPreservesMoodDimension() {
        let model = TimelineModel()
        let tagID = UUID()
        model.activeFilter = FilterCondition(tagIDs: [tagID], mood: .happy)

        model.discardFilterTag(tagID)

        XCTAssertEqual(model.activeFilter?.mood, .happy)
        XCTAssertEqual(model.activeFilter?.tagIDs, [])
    }

    /// 待清理 id 不在当前筛选里（未筛选该标签，或已被清理过）：无操作，不产生副作用。
    func testDiscardFilterTagIsNoOpWhenIDNotInFilter() {
        let model = TimelineModel()
        let tagID = UUID()
        let unrelatedFilter = FilterCondition(mood: .sad)
        model.activeFilter = unrelatedFilter

        model.discardFilterTag(tagID)

        XCTAssertEqual(model.activeFilter, unrelatedFilter)
    }

    /// `activeFilter` 为 `nil` 时调用不应崩溃、不应意外创建筛选。
    func testDiscardFilterTagIsNoOpWhenNoActiveFilter() {
        let model = TimelineModel()

        model.discardFilterTag(UUID())

        XCTAssertNil(model.activeFilter)
    }

    /// 定位状态（`heatmapFocusDate`）与本操作完全独立（公理2「定位 ≠ 筛选」）。
    func testDiscardFilterTagDoesNotAffectHeatmapFocusDate() {
        let model = TimelineModel()
        let tagID = UUID()
        let focusDate = Date.now
        model.activeFilter = FilterCondition(tagIDs: [tagID])
        model.setHeatmapAnchor(focusDate, granularity: .month)

        model.discardFilterTag(tagID)

        XCTAssertEqual(model.heatmapFocusDate, focusDate)
        XCTAssertEqual(model.heatmapAnchorGranularity, .month)
    }

    func testDirectHeatmapFocusDateWriteDefaultsToDayGranularity() {
        let model = TimelineModel()

        model.heatmapFocusDate = Date.now

        XCTAssertEqual(model.heatmapAnchorGranularity, .day)
    }

    func testClearHeatmapAnchorClearsDateAndGranularity() {
        let model = TimelineModel()
        model.setHeatmapAnchor(Date.now, granularity: .month)

        model.clearHeatmapAnchor()

        XCTAssertNil(model.heatmapFocusDate)
        XCTAssertNil(model.heatmapAnchorGranularity)
    }
}
