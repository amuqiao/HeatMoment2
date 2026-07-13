import GRDB
import XCTest
@testable import HeatMoment

final class CanonicalStoreTests: XCTestCase {
    func testMigrationCreatesMetadataAndCanOpenExistingStore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let dbURL = directory.appendingPathComponent("Library.sqlite")
        let firstStore = try CanonicalStore(path: dbURL.path)
        let firstRepository = CanonicalLibraryRepository(store: firstStore)
        let firstMetadata = try await firstRepository.metadata()

        let reopenedStore = try CanonicalStore(path: dbURL.path)
        let reopenedRepository = CanonicalLibraryRepository(store: reopenedStore)
        let reopenedMetadata = try await reopenedRepository.metadata()

        XCTAssertEqual(firstMetadata.libraryID, reopenedMetadata.libraryID)
        XCTAssertEqual(reopenedMetadata.schemaVersion, CanonicalStore.currentSchemaVersion)
    }

    func testMomentLifecycleWritesMutationLogAndQueryStates() async throws {
        let repository = try makeRepository()
        let tag = try await repository.createOrReuseTag(
            name: "工作", now: Date(timeIntervalSince1970: 50))
        let momentID = try await repository.createMoment(
            title: "标题",
            bodyText: "正文",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .happy,
            tagIDs: [tag.id],
            now: Date(timeIntervalSince1970: 200)
        )

        var page = try await repository.fetchPage()
        XCTAssertEqual(page.map(\.id), [momentID])
        XCTAssertEqual(page.first?.tagIDs, [tag.id])
        let countAfterCreate = try await repository.totalMomentCount()
        XCTAssertEqual(countAfterCreate, 1)

        try await repository.softDeleteMoment(id: momentID, now: Date(timeIntervalSince1970: 300))
        let pageAfterDelete = try await repository.fetchPage()
        XCTAssertTrue(pageAfterDelete.isEmpty)
        let trash = try await repository.fetchTrash()
        XCTAssertEqual(trash.map(\.id), [momentID])
        XCTAssertEqual(trash.first?.deletedAt, Date(timeIntervalSince1970: 300))

        try await repository.restoreMoment(id: momentID, now: Date(timeIntervalSince1970: 400))
        page = try await repository.fetchPage()
        XCTAssertEqual(page.map(\.id), [momentID])
        XCTAssertNil(page.first?.deletedAt)

        try await repository.purgeMoment(id: momentID, now: Date(timeIntervalSince1970: 500))
        let pageAfterPurge = try await repository.fetchPage()
        let trashAfterPurge = try await repository.fetchTrash()
        let pendingPurge = try await repository.fetchPurgePendingMoments()
        let countAfterPurge = try await repository.totalMomentCount()
        XCTAssertTrue(pageAfterPurge.isEmpty)
        XCTAssertTrue(trashAfterPurge.isEmpty)
        XCTAssertEqual(pendingPurge.map(\.id), [momentID])
        XCTAssertEqual(pendingPurge.first?.lifecycleState, .purgePending)
        XCTAssertNil(pendingPurge.first?.purgedAt)
        XCTAssertEqual(countAfterPurge, 0)

        await assertMomentNotFound(momentID) {
            try await repository.restoreMoment(id: momentID)
        }
        let mutationLog = try await repository.fetchMutationLog()
        let operations = mutationLog.map(\.operation)
        XCTAssertEqual(operations, ["create", "create", "softDelete", "restore", "purge"])
    }

    func testMomentCreateRollsBackWhenTagIsMissing() async throws {
        let repository = try makeRepository()
        let missingTagID = UUID()

        await assertTagNotFound(missingTagID) {
            _ = try await repository.createMoment(
                title: "不会写入",
                bodyText: "",
                occurredAt: .now,
                mood: .normal,
                tagIDs: [missingTagID]
            )
        }

        let page = try await repository.fetchPage()
        let mutationLog = try await repository.fetchMutationLog()
        XCTAssertTrue(page.isEmpty)
        XCTAssertTrue(mutationLog.isEmpty)
    }

    func testMomentUpdateRollsBackWhenTagIsMissing() async throws {
        let repository = try makeRepository()
        let momentID = try await repository.createMoment(
            title: "原标题",
            bodyText: "原正文",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .normal,
            now: Date(timeIntervalSince1970: 200)
        )
        let missingTagID = UUID()

        await assertTagNotFound(missingTagID) {
            try await repository.updateMoment(
                id: momentID,
                title: "不应写入",
                tagIDs: [missingTagID],
                now: Date(timeIntervalSince1970: 300)
            )
        }

        let page = try await repository.fetchPage()
        XCTAssertEqual(page.first?.title, "原标题")
        XCTAssertTrue(page.first?.tagIDs.isEmpty == true)
        let mutationLog = try await repository.fetchMutationLog()
        XCTAssertEqual(mutationLog.map(\.operation), ["create"])
    }

    func testMomentTagOrderRoundTrips() async throws {
        let repository = try makeRepository()
        let first = try await repository.createOrReuseTag(
            name: "工作", now: Date(timeIntervalSince1970: 10))
        let second = try await repository.createOrReuseTag(
            name: "生活", now: Date(timeIntervalSince1970: 20))
        let third = try await repository.createOrReuseTag(
            name: "灵感", now: Date(timeIntervalSince1970: 30))

        let momentID = try await repository.createMoment(
            title: "多标签",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .normal,
            tagIDs: [third.id, first.id, second.id],
            now: Date(timeIntervalSince1970: 200)
        )

        let page = try await repository.fetchPage()
        XCTAssertEqual(page.map(\.id), [momentID])
        XCTAssertEqual(page.first?.tagIDs, [third.id, first.id, second.id])
    }

    func testTagCreateReuseRenameAndDelete() async throws {
        let repository = try makeRepository()

        let created = try await repository.createOrReuseTag(name: "旅行")
        let reused = try await repository.createOrReuseTag(name: "旅行")
        XCTAssertTrue(created.didCreate)
        XCTAssertFalse(reused.didCreate)
        XCTAssertEqual(created.id, reused.id)
        let tagCount = try await repository.totalTagCount()
        XCTAssertEqual(tagCount, 1)

        try await repository.renameTag(id: created.id, newName: "兴趣")
        let tags = try await repository.fetchAllTags()
        XCTAssertEqual(tags.map(\.name), ["兴趣"])

        try await repository.deleteTag(id: created.id)
        let tagsAfterDelete = try await repository.fetchAllTags()
        XCTAssertTrue(tagsAfterDelete.isEmpty)

        let mutationLog = try await repository.fetchMutationLog()
        let operations = mutationLog.map(\.operation)
        XCTAssertEqual(operations, ["create", "rename", "delete"])
    }

    func testCreateTagChecksQuotaInsideTransaction() async throws {
        let repository = try makeRepository()
        let quotaService = QuotaService()

        for index in 0..<Quota.freeTagLimit {
            _ = try await repository.createOrReuseTag(
                name: "tag-\(index)",
                quotaService: quotaService,
                now: Date(timeIntervalSince1970: Double(index))
            )
        }

        do {
            _ = try await repository.createOrReuseTag(
                name: "overflow",
                quotaService: quotaService,
                now: Date(timeIntervalSince1970: 100)
            )
            XCTFail("期望抛出 RepositoryError.quotaExceeded，但没有抛出")
        } catch RepositoryError.quotaExceeded(let kind) {
            XCTAssertEqual(kind, .tags)
        } catch {
            XCTFail("期望 RepositoryError.quotaExceeded，实际抛出 \(error)")
        }

        let tags = try await repository.fetchAllTags()
        XCTAssertEqual(tags.map(\.name), ["tag-0", "tag-1", "tag-2"])
        let mutationLog = try await repository.fetchMutationLog()
        XCTAssertEqual(mutationLog.count, Quota.freeTagLimit)
    }

    func testDeleteReferencedTagBumpsMomentAndWritesTombstone() async throws {
        let store = try CanonicalStore.makeInMemory()
        let repository = CanonicalLibraryRepository(store: store)
        let deletedTag = try await repository.createOrReuseTag(
            name: "工作", now: Date(timeIntervalSince1970: 10))
        let remainingTag = try await repository.createOrReuseTag(
            name: "生活", now: Date(timeIntervalSince1970: 20))
        let momentID = try await repository.createMoment(
            title: "带标签",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .happy,
            tagIDs: [deletedTag.id, remainingTag.id],
            now: Date(timeIntervalSince1970: 30)
        )

        try await repository.deleteTag(id: deletedTag.id, now: Date(timeIntervalSince1970: 40))

        let page = try await repository.fetchPage()
        XCTAssertEqual(page.map(\.id), [momentID])
        XCTAssertEqual(page.first?.tagIDs, [remainingTag.id])
        XCTAssertEqual(page.first?.revision, 2)

        let mutationLog = try await repository.fetchMutationLog()
        XCTAssertEqual(
            mutationLog.map(\.operation), ["create", "create", "create", "tagDetach", "delete"])
        let tagTombstones = try store.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM tombstone_record
                    WHERE entity_type = ? AND entity_id = ? AND operation = ?
                    """,
                arguments: ["tag", deletedTag.id.uuidString, "delete"]
            ) ?? 0
        }
        XCTAssertEqual(tagTombstones, 1)
    }

    func testRenameTagToExistingNameFailsWithoutPartialWrite() async throws {
        let repository = try makeRepository()
        let first = try await repository.createOrReuseTag(name: "工作")
        let second = try await repository.createOrReuseTag(name: "生活")

        do {
            try await repository.renameTag(id: second.id, newName: "工作")
            XCTFail("期望重名失败，但 rename 成功了")
        } catch RepositoryError.tagNameConflict(let name) {
            XCTAssertEqual(name, "工作")
        }

        let tags = try await repository.fetchAllTags()
        XCTAssertEqual(Set(tags.map(\.name)), ["工作", "生活"])
        let mutationLog = try await repository.fetchMutationLog()
        XCTAssertEqual(mutationLog.count, 2)
        XCTAssertNotEqual(first.id, second.id)
    }

    func testMomentAssetLinksPreserveUniqueSortOrder() throws {
        let store = try CanonicalStore.makeInMemory()
        let momentID = UUID()
        let firstAssetID = UUID()
        let secondAssetID = UUID()
        let now = Date(timeIntervalSince1970: 100)

        try store.write { db in
            try insertMoment(id: momentID, now: now, db: db)
            try insertAsset(id: firstAssetID, createdAt: now, db: db)
            try insertAsset(id: secondAssetID, createdAt: now, db: db)

            try insertAssetLink(
                momentID: momentID, assetID: firstAssetID, sortIndex: 1, now: now, db: db)
            try insertAssetLink(
                momentID: momentID, assetID: secondAssetID, sortIndex: 0, now: now, db: db)

            let orderedAssetIDs = try String.fetchAll(
                db,
                sql: """
                    SELECT asset_id FROM moment_asset_link
                    WHERE moment_id = ?
                    ORDER BY sort_index ASC
                    """,
                arguments: [momentID.uuidString]
            )
            XCTAssertEqual(orderedAssetIDs, [secondAssetID.uuidString, firstAssetID.uuidString])

            let duplicateAssetID = UUID()
            try insertAsset(id: duplicateAssetID, createdAt: now, db: db)
            XCTAssertThrowsError(
                try insertAssetLink(
                    momentID: momentID, assetID: duplicateAssetID, sortIndex: 0, now: now, db: db)
            ) { error in
                XCTAssertNotNil(error as? DatabaseError)
            }
        }
    }

    private func makeRepository() throws -> CanonicalLibraryRepository {
        CanonicalLibraryRepository(store: try CanonicalStore.makeInMemory())
    }

    private func insertMoment(id: UUID, now: Date, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO moment_record (
                    id, title, body_text, occurred_at, created_at, updated_at,
                    mood_raw_value, lifecycle_state, deleted_at, purged_at, revision
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?)
                """,
            arguments: [
                id.uuidString,
                "有照片的时刻",
                "",
                now.timeIntervalSince1970,
                now.timeIntervalSince1970,
                now.timeIntervalSince1970,
                Mood.normal.rawValue,
                CanonicalMomentLifecycleState.active.rawValue,
                1,
            ]
        )
    }

    private func insertAsset(id: UUID, createdAt: Date, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO asset_record (
                    id, content_hash, mime_type, byte_count, width, height, created_at,
                    reference_state, pin_count
                ) VALUES (?, ?, ?, ?, NULL, NULL, ?, ?, ?)
                """,
            arguments: [
                id.uuidString,
                "sha256-\(id.uuidString)",
                "image/jpeg",
                42,
                createdAt.timeIntervalSince1970,
                "referenced",
                0,
            ]
        )
    }

    private func insertAssetLink(
        momentID: UUID,
        assetID: UUID,
        sortIndex: Int,
        now: Date,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO moment_asset_link (moment_id, asset_id, sort_index, created_at)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [
                momentID.uuidString,
                assetID.uuidString,
                sortIndex,
                now.timeIntervalSince1970,
            ]
        )
    }

    private func assertMomentNotFound(
        _ id: UUID,
        operation: () async throws -> Void,
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

    private func assertTagNotFound(
        _ id: UUID,
        operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("期望抛出 RepositoryError.tagNotFound，但没有抛出", file: file, line: line)
        } catch RepositoryError.tagNotFound(let notFoundID) {
            XCTAssertEqual(notFoundID, id, file: file, line: line)
        } catch {
            XCTFail("期望 RepositoryError.tagNotFound，实际抛出 \(error)", file: file, line: line)
        }
    }
}
