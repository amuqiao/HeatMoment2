import GRDB
import XCTest
@testable import HeatMoment

final class CanonicalStoreMigrationIdentifierTests: XCTestCase {
    func testMigrationKeepsExistingV2IdentifierStable() throws {
        let store = try CanonicalStore.makeInMemory()
        let appliedMigrations = try store.read { db in
            try Set(String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations"))
        }

        XCTAssertTrue(appliedMigrations.contains("v2_swift_data_import_marker"))
        XCTAssertFalse(appliedMigrations.contains("v2_canonical_metadata_version"))
    }

    func testV6MigrationMarksExistingEmptyLibrarySeeded() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CanonicalStoreMigrationIdentifierTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dbURL = directory.appendingPathComponent("Library.sqlite")
        try makeLegacyV5Database(at: dbURL)

        let store = try CanonicalStore(path: dbURL.path)

        let seedVersion = try store.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT default_seed_version FROM library_metadata WHERE id = 1"
            )
        }
        XCTAssertEqual(seedVersion, CanonicalStore.currentDefaultSeedVersion)
    }

    func testFreshV6LibraryStartsUnseeded() throws {
        let store = try CanonicalStore.makeInMemory()

        let seedVersion = try store.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT default_seed_version FROM library_metadata WHERE id = 1"
            )
        }
        XCTAssertEqual(seedVersion, 0)
    }

    private func makeLegacyV5Database(at url: URL) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
            for identifier in [
                "v1_canonical_core",
                "v2_swift_data_import_marker",
                "v3_asset_pin_record",
                "v4_recovery_point_catalog",
                "v5_recovery_point_used_tag_count"
            ] {
                try db.execute(
                    sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                    arguments: [identifier]
                )
            }
            try db.execute(
                sql: """
                    CREATE TABLE library_metadata (
                        id INTEGER PRIMARY KEY,
                        library_id TEXT NOT NULL,
                        schema_version INTEGER NOT NULL,
                        device_id TEXT NOT NULL,
                        sync_epoch TEXT NOT NULL,
                        created_at DOUBLE NOT NULL,
                        updated_at DOUBLE NOT NULL
                    )
                    """
            )
            try db.execute(
                sql: """
                    INSERT INTO library_metadata (
                        id, library_id, schema_version, device_id, sync_epoch, created_at, updated_at
                    ) VALUES (1, ?, 5, ?, ?, 0, 0)
                    """,
                arguments: [UUID().uuidString, UUID().uuidString, UUID().uuidString]
            )
            try db.execute(
                sql: """
                    CREATE TABLE moment_record (
                        id TEXT PRIMARY KEY,
                        title TEXT NOT NULL,
                        body_text TEXT NOT NULL,
                        occurred_at DOUBLE NOT NULL,
                        created_at DOUBLE NOT NULL,
                        updated_at DOUBLE NOT NULL,
                        mood_raw_value INTEGER NOT NULL,
                        lifecycle_state TEXT NOT NULL,
                        deleted_at DOUBLE,
                        purged_at DOUBLE,
                        revision INTEGER NOT NULL
                    )
                    """
            )
            try db.execute(
                sql: """
                    CREATE TABLE tag_record (
                        id TEXT PRIMARY KEY,
                        name TEXT NOT NULL,
                        created_at DOUBLE NOT NULL,
                        revision INTEGER NOT NULL
                    )
                    """
            )
        }
    }
}
