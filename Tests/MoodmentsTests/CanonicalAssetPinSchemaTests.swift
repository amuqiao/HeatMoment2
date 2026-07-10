import GRDB
import XCTest
@testable import Moodments

final class CanonicalAssetPinSchemaTests: XCTestCase {
    func testMigrationCreatesAssetPinTableAndIndexes() throws {
        let store = try CanonicalStore.makeInMemory()

        XCTAssertEqual(try assetPinTableCount(in: store), 1)
        XCTAssertEqual(try assetPinIndexNames(in: store), expectedAssetPinIndexNames)
    }

    func testMigrationUpgradesV2StoreToAssetPinSchema() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CanonicalAssetPinSchemaTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let dbURL = directory.appendingPathComponent("Library.sqlite")
        _ = try CanonicalStore(path: dbURL.path)
        try simulateV2Store(at: dbURL)

        let upgradedStore = try CanonicalStore(path: dbURL.path)
        let schemaVersion = try upgradedStore.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT schema_version FROM library_metadata WHERE id = 1"
            ) ?? 0
        }
        let appliedMigrations = try upgradedStore.read { db in
            try Set(String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations"))
        }

        XCTAssertEqual(schemaVersion, 3)
        XCTAssertTrue(appliedMigrations.contains("v3_asset_pin_record"))
        XCTAssertEqual(try assetPinTableCount(in: upgradedStore), 1)
        XCTAssertEqual(try assetPinIndexNames(in: upgradedStore), expectedAssetPinIndexNames)
    }

    private var expectedAssetPinIndexNames: Set<String> {
        [
            "idx_asset_record_content_hash",
            "idx_asset_pin_record_content_hash",
            "idx_asset_pin_record_owner",
            "idx_asset_pin_record_expires_at",
        ]
    }

    private func assetPinTableCount(in store: CanonicalStore) throws -> Int {
        let tableCount = try store.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM sqlite_master
                    WHERE type = 'table' AND name = 'asset_pin_record'
                    """
            ) ?? 0
        }
        return tableCount
    }

    private func assetPinIndexNames(in store: CanonicalStore) throws -> Set<String> {
        try store.read { db in
            try Set(
                String.fetchAll(
                    db,
                    sql: """
                        SELECT name
                        FROM sqlite_master
                        WHERE type = 'index'
                            AND name IN (
                                'idx_asset_record_content_hash',
                                'idx_asset_pin_record_content_hash',
                                'idx_asset_pin_record_owner',
                                'idx_asset_pin_record_expires_at'
                            )
                        """
                )
            )
        }
    }

    private func simulateV2Store(at dbURL: URL) throws {
        let dbQueue = try DatabaseQueue(path: dbURL.path)
        try dbQueue.write { db in
            try db.execute(sql: "DROP TABLE IF EXISTS asset_pin_record")
            try db.execute(sql: "DROP INDEX IF EXISTS idx_asset_record_content_hash")
            try db.execute(sql: "UPDATE library_metadata SET schema_version = 2 WHERE id = 1")
            try db.execute(
                sql: "DELETE FROM grdb_migrations WHERE identifier = 'v3_asset_pin_record'"
            )
        }
    }
}
