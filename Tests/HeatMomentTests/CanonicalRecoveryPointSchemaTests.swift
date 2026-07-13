import GRDB
import XCTest
@testable import HeatMoment

final class CanonicalRecoveryPointSchemaTests: XCTestCase {
    func testMigrationCreatesRecoveryPointCatalogTablesAndIndexes() throws {
        let store = try CanonicalStore.makeInMemory()

        XCTAssertEqual(try tableCount(named: "recovery_point_record", in: store), 1)
        XCTAssertEqual(try tableCount(named: "recovery_point_asset_record", in: store), 1)
        XCTAssertEqual(try recoveryPointIndexNames(in: store), expectedRecoveryPointIndexNames)
        XCTAssertTrue(try recoveryPointColumns(in: store).contains("used_tag_count"))
        XCTAssertFalse(try recoveryPointColumns(in: store).contains("tag_count"))
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
        XCTAssertTrue(appliedMigrations.contains("v5_recovery_point_used_tag_count"))
        XCTAssertEqual(try tableCount(named: "recovery_point_record", in: upgradedStore), 1)
        XCTAssertEqual(try tableCount(named: "recovery_point_asset_record", in: upgradedStore), 1)
        XCTAssertEqual(
            try recoveryPointIndexNames(in: upgradedStore),
            expectedRecoveryPointIndexNames
        )
        XCTAssertTrue(try recoveryPointColumns(in: upgradedStore).contains("used_tag_count"))
        XCTAssertFalse(try recoveryPointColumns(in: upgradedStore).contains("tag_count"))
    }

    func testMigrationUpgradesV4RecoveryPointCatalogToUsedTagCount() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CanonicalRecoveryPointV4SchemaTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let descriptor = CanonicalStoreDescriptor(
            rootDirectory: directory,
            databaseFileName: "Library.sqlite"
        )
        let dbURL = descriptor.databaseURL
        _ = try CanonicalStore(path: dbURL.path)
        try simulateV4StoreWithLegacyRecoveryPointCatalog(at: dbURL)
        let legacyDirectory = descriptor.recoveryPointDirectoryURL.appendingPathComponent(
            "legacy",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )

        let upgradedRuntime = try CanonicalLibraryRuntime(descriptor: descriptor)
        let upgradedStore = upgradedRuntime.store

        XCTAssertEqual(try recoveryPointCount(in: upgradedStore), 0)
        XCTAssertEqual(try recoveryPointPinCount(in: upgradedStore), 0)
        XCTAssertTrue(try recoveryPointColumns(in: upgradedStore).contains("used_tag_count"))
        XCTAssertFalse(try recoveryPointColumns(in: upgradedStore).contains("tag_count"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDirectory.path))
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

    private func recoveryPointCount(in store: CanonicalStore) throws -> Int {
        try store.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM recovery_point_record") ?? 0
        }
    }

    private func recoveryPointPinCount(in store: CanonicalStore) throws -> Int {
        try store.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM asset_pin_record
                    WHERE owner_kind = 'recoveryPoint'
                    """
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

    private func recoveryPointColumns(in store: CanonicalStore) throws -> Set<String> {
        try store.read { db in
            try Set(
                String.fetchAll(
                    db,
                    sql: """
                        SELECT name
                        FROM pragma_table_info('recovery_point_record')
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
            try db.execute(
                sql: """
                    DELETE FROM grdb_migrations
                    WHERE identifier = 'v5_recovery_point_used_tag_count'
                    """
            )
        }
    }

    private func simulateV4StoreWithLegacyRecoveryPointCatalog(at dbURL: URL) throws {
        let dbQueue = try DatabaseQueue(path: dbURL.path)
        try dbQueue.write { db in
            try db.execute(sql: "DROP TABLE IF EXISTS recovery_point_asset_record")
            try db.execute(sql: "DROP TABLE IF EXISTS recovery_point_record")
            try db.create(table: "recovery_point_record") { table in
                table.column("id", .text).primaryKey()
                table.column("created_at", .double).notNull()
                table.column("reason", .text).notNull()
                table.column("status", .text).notNull()
                table.column("schema_version", .integer).notNull()
                table.column("app_version", .text).notNull()
                table.column("source_library_id", .text).notNull()
                table.column("sqlite_snapshot_relative_path", .text).notNull()
                table.column("sqlite_snapshot_byte_count", .integer).notNull()
                table.column("sqlite_snapshot_sha256", .text).notNull()
                table.column("record_count", .integer).notNull()
                table.column("tag_count", .integer).notNull()
                table.column("asset_count", .integer).notNull()
            }
            try db.create(table: "recovery_point_asset_record") { table in
                table.column("recovery_point_id", .text).notNull()
                    .references("recovery_point_record", column: "id", onDelete: .cascade)
                table.column("asset_id", .text).notNull()
                table.column("content_hash", .text).notNull()
                table.column("byte_count", .integer).notNull()
                table.column("relative_path", .text).notNull()
                table.primaryKey(["recovery_point_id", "asset_id"])
            }
            try db.execute(
                sql: """
                    INSERT INTO recovery_point_record (
                        id, created_at, reason, status, schema_version, app_version,
                        source_library_id, sqlite_snapshot_relative_path,
                        sqlite_snapshot_byte_count, sqlite_snapshot_sha256,
                        record_count, tag_count, asset_count
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    "00000000-0000-0000-0000-00000000A401",
                    100,
                    "stableChanges",
                    "available",
                    4,
                    "1.0.8",
                    "00000000-0000-0000-0000-00000000A402",
                    "RecoveryPoints/legacy/Library.sqlite",
                    1,
                    String(repeating: "a", count: 64),
                    1,
                    3,
                    0,
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO asset_pin_record (
                        id, content_hash, owner_kind, owner_id, created_at, expires_at
                    ) VALUES (?, ?, ?, ?, ?, NULL)
                    """,
                arguments: [
                    "00000000-0000-0000-0000-00000000A403",
                    String(repeating: "b", count: 64),
                    "recoveryPoint",
                    "00000000-0000-0000-0000-00000000A401",
                    100,
                ]
            )
            try db.execute(
                sql: "UPDATE library_metadata SET schema_version = 4 WHERE id = 1"
            )
            try db.execute(
                sql: """
                    DELETE FROM grdb_migrations
                    WHERE identifier = 'v5_recovery_point_used_tag_count'
                    """
            )
        }
    }
}
