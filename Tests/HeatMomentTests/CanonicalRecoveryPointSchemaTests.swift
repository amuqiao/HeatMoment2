import GRDB
import XCTest
@testable import HeatMoment

final class CanonicalRecoveryPointSchemaTests: XCTestCase {
    func testMigrationCreatesRecoveryPointCatalogTablesAndIndexes() throws {
        let store = try CanonicalStore.makeInMemory()

        XCTAssertEqual(try tableCount(named: "recovery_point_record", in: store), 1)
        XCTAssertEqual(try tableCount(named: "recovery_point_asset_record", in: store), 1)
        XCTAssertEqual(try recoveryPointIndexNames(in: store), expectedRecoveryPointIndexNames)
    }

    func testMigrationUpgradesV3StoreToRecoveryPointCatalog() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CanonicalRecoveryPointSchemaTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let dbURL = directory.appendingPathComponent("Library.sqlite")
        _ = try CanonicalStore(path: dbURL.path)
        try simulateV3Store(at: dbURL)

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

        XCTAssertEqual(schemaVersion, CanonicalStore.currentSchemaVersion)
        XCTAssertTrue(appliedMigrations.contains("v4_recovery_point_catalog"))
        XCTAssertEqual(try tableCount(named: "recovery_point_record", in: upgradedStore), 1)
        XCTAssertEqual(try tableCount(named: "recovery_point_asset_record", in: upgradedStore), 1)
        XCTAssertEqual(
            try recoveryPointIndexNames(in: upgradedStore),
            expectedRecoveryPointIndexNames
        )
    }

    private var expectedRecoveryPointIndexNames: Set<String> {
        [
            "idx_recovery_point_record_created_at",
            "idx_recovery_point_asset_record_content_hash"
        ]
    }

    private func tableCount(named tableName: String, in store: CanonicalStore) throws -> Int {
        try store.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM sqlite_master
                    WHERE type = 'table' AND name = ?
                    """,
                arguments: [tableName]
            ) ?? 0
        }
    }

    private func recoveryPointIndexNames(in store: CanonicalStore) throws -> Set<String> {
        try store.read { db in
            try Set(
                String.fetchAll(
                    db,
                    sql: """
                        SELECT name
                        FROM sqlite_master
                        WHERE type = 'index'
                            AND name IN (
                                'idx_recovery_point_record_created_at',
                                'idx_recovery_point_asset_record_content_hash'
                            )
                        """
                )
            )
        }
    }

    private func simulateV3Store(at dbURL: URL) throws {
        let dbQueue = try DatabaseQueue(path: dbURL.path)
        try dbQueue.write { db in
            try db.execute(sql: "DROP TABLE IF EXISTS recovery_point_asset_record")
            try db.execute(sql: "DROP TABLE IF EXISTS recovery_point_record")
            try db.execute(sql: "UPDATE library_metadata SET schema_version = 3 WHERE id = 1")
            try db.execute(
                sql: "DELETE FROM grdb_migrations WHERE identifier = 'v4_recovery_point_catalog'"
            )
        }
    }
}
