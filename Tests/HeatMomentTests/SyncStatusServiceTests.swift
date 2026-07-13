import XCTest
@testable import HeatMoment

/// `SyncStatusService.evaluate(_:)` 纯逻辑推导测试（见 `docs/plans/implementation-plan.md` §9.2）：
/// 不依赖真实网络/CloudKit，直接构造 `SyncStatusEvaluationInput` 验证三态推导。
final class SyncStatusServiceTests: XCTestCase {
    func testCloudKitDisabledIsAlwaysOffline() {
        let status = SyncStatusService.evaluate(SyncStatusEvaluationInput(
            cloudKitEnabled: false, isNetworkReachable: true, lastLocalWriteAt: nil, now: .now
        ))
        XCTAssertEqual(status, .offline)
    }

    func testNetworkUnreachableIsOffline() {
        let status = SyncStatusService.evaluate(SyncStatusEvaluationInput(
            cloudKitEnabled: true, isNetworkReachable: false, lastLocalWriteAt: nil, now: .now
        ))
        XCTAssertEqual(status, .offline)
    }

    func testRecentLocalWriteIsSyncing() {
        let now = Date.now
        let status = SyncStatusService.evaluate(SyncStatusEvaluationInput(
            cloudKitEnabled: true, isNetworkReachable: true,
            lastLocalWriteAt: now.addingTimeInterval(-1), now: now
        ))
        XCTAssertEqual(status, .syncing)
    }

    func testStaleLocalWriteIsSynced() {
        let now = Date.now
        let status = SyncStatusService.evaluate(SyncStatusEvaluationInput(
            cloudKitEnabled: true, isNetworkReachable: true,
            lastLocalWriteAt: now.addingTimeInterval(-SyncStatusService.syncingWindow - 1), now: now
        ))
        XCTAssertEqual(status, .synced)
    }

    func testNoLocalWriteRecordIsSynced() {
        let status = SyncStatusService.evaluate(SyncStatusEvaluationInput(
            cloudKitEnabled: true, isNetworkReachable: true, lastLocalWriteAt: nil, now: .now
        ))
        XCTAssertEqual(status, .synced)
    }

    @MainActor
    func testInitialStatusReflectsCloudKitEnabled() {
        XCTAssertEqual(SyncStatusService(cloudKitEnabled: true).status, .synced)
        XCTAssertEqual(SyncStatusService(cloudKitEnabled: false).status, .offline)
    }
}
