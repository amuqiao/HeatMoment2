import XCTest
import SwiftData
@testable import Moodments

/// `Moment` 软删除生命周期测试：见 `docs/product-mental-model.md` 公理 3（删除是生命周期）
/// 与 `docs/design/07-data-persistence.md` §3（额度计数含垃圾箱、与列表查询分离）。
final class MomentLifecycleTests: XCTestCase {
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

    func testSoftDeleteSetsIsDeletedAndDeletedAt() async throws {
        let id = try await repository.createMoment(
            title: "t", bodyText: "b", occurredAt: .now, mood: .happy)

        try await repository.softDelete(id: id)

        let trash = try await repository.fetchTrash()
        XCTAssertEqual(trash.count, 1)
        XCTAssertEqual(trash.first?.id, id)
        XCTAssertEqual(trash.first?.isDeleted, true)
        XCTAssertNotNil(trash.first?.deletedAt)
    }

    func testRestoreClearsDeletedState() async throws {
        let id = try await repository.createMoment(
            title: "t", bodyText: "b", occurredAt: .now, mood: .happy)
        try await repository.softDelete(id: id)

        try await repository.restore(id: id)

        let page = try await repository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(page.count, 1)
        XCTAssertEqual(page.first?.isDeleted, false)
        XCTAssertNil(page.first?.deletedAt)
        let trash = try await repository.fetchTrash()
        XCTAssertTrue(trash.isEmpty)
    }

    func testPurgeRemovesRecordPhysically() async throws {
        let id = try await repository.createMoment(
            title: "t", bodyText: "b", occurredAt: .now, mood: .happy)
        try await repository.softDelete(id: id)

        try await repository.purge(id: id)

        let total = try await repository.totalMomentCount()
        XCTAssertEqual(total, 0)
        let trash = try await repository.fetchTrash()
        XCTAssertTrue(trash.isEmpty)
    }

    /// 额度计数含垃圾箱内 `isDeleted==true` 的记录；时间轴列表查询只含未软删除记录——两个不同查询。
    func testQuotaCountIncludesTrashWhileListQueryExcludesIt() async throws {
        let activeID = try await repository.createMoment(
            title: "active", bodyText: "", occurredAt: .now, mood: .normal
        )
        let trashedID = try await repository.createMoment(
            title: "trashed", bodyText: "", occurredAt: .now, mood: .sad
        )
        try await repository.softDelete(id: trashedID)

        // 断言一：额度计数口径——含垃圾箱内软删除记录。
        let quotaCount = try await repository.totalMomentCount()
        XCTAssertEqual(quotaCount, 2)

        // 断言二：列表查询口径——只查未软删除记录。
        let listPage = try await repository.fetchPage(offset: 0, limit: 10)
        XCTAssertEqual(listPage.count, 1)
        XCTAssertEqual(listPage.first?.id, activeID)
    }

    /// 对不存在的 id 操作必须快速失败，不允许静默 no-op（见 `CLAUDE.md`「不擅自添加兜底策略」）。
    func testOperationsOnMissingIDThrow() async throws {
        let missingID = UUID()

        await assertThrowsMomentNotFound(missingID) {
            try await self.repository.softDelete(id: missingID)
        }
        await assertThrowsMomentNotFound(missingID) {
            try await self.repository.restore(id: missingID)
        }
        await assertThrowsMomentNotFound(missingID) {
            try await self.repository.purge(id: missingID)
        }
        await assertThrowsMomentNotFound(missingID) {
            try await self.repository.updateMoment(id: missingID, title: "x")
        }
    }

    private func assertThrowsMomentNotFound(
        _ id: UUID,
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("期望抛出 RepositoryError.momentNotFound，但没有抛出", file: file, line: line)
        } catch RepositoryError.momentNotFound(let notFoundID) {
            XCTAssertEqual(notFoundID, id, file: file, line: line)
        } catch {
            XCTFail("期望 RepositoryError.momentNotFound，实际抛出 \(error)", file: file, line: line)
        }
    }
}

/// 磁盘往返回归测试：验证 `Moment.deletedFlag`（对外暴露为 `isDeleted`）经真实落盘、
/// 关闭并用全新 `ModelContainer` 重新打开后仍保持正确值——专门锁住此前发现的
/// SwiftData「`is` 前缀 Bool 属性在 `save()` 后被重置」的框架缺陷回归（见 `Moment.swift` 注释）。
/// 用内存容器无法复现该问题，故这里必须落盘到临时目录。
final class MomentDiskRoundTripTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoodmentsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    func testSoftDeleteSurvivesDiskRoundTrip() async throws {
        let storeURL = tempDirectory.appendingPathComponent("Moodments.store")
        let id: UUID
        do {
            let container = try ModelContainerConfig.makeContainer(at: storeURL)
            let repository = MomentRepository(modelContainer: container)
            id = try await repository.createMoment(
                title: "disk", bodyText: "b", occurredAt: .now, mood: .happy
            )
            try await repository.softDelete(id: id)
        }

        // 用全新的 ModelContainer 重新打开同一磁盘存储，强制从磁盘读取而非复用内存对象图。
        let reopenedContainer = try ModelContainerConfig.makeContainer(at: storeURL)
        let reopenedRepository = MomentRepository(modelContainer: reopenedContainer)

        let trash = try await reopenedRepository.fetchTrash()
        XCTAssertEqual(trash.count, 1)
        XCTAssertEqual(trash.first?.id, id)
        XCTAssertEqual(trash.first?.isDeleted, true, "isDeleted 在磁盘往返后不应被重置为 false")
        XCTAssertNotNil(trash.first?.deletedAt)

        let page = try await reopenedRepository.fetchPage(offset: 0, limit: 10)
        XCTAssertTrue(page.isEmpty, "已软删除的记录不应出现在列表查询中")
    }
}
