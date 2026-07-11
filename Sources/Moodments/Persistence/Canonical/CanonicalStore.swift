import Foundation
import GRDB

final class CanonicalStore: @unchecked Sendable {
    static let currentSchemaVersion = 4

    private let dbQueue: DatabaseQueue

    convenience init(path: String) throws {
        try self.init(dbQueue: DatabaseQueue(path: path))
    }

    static func makeInMemory() throws -> CanonicalStore {
        try CanonicalStore(dbQueue: DatabaseQueue())
    }

    private init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrator.migrate(dbQueue)
    }

    func read<Value>(_ block: (Database) throws -> Value) throws -> Value {
        try dbQueue.read(block)
    }

    func write<Value>(_ block: (Database) throws -> Value) throws -> Value {
        try dbQueue.write(block)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_canonical_core") { db in
            try db.create(table: "library_metadata") { table in
                table.column("id", .integer).primaryKey()
                table.column("library_id", .text).notNull()
                table.column("schema_version", .integer).notNull()
                table.column("device_id", .text).notNull()
                table.column("sync_epoch", .text).notNull()
                table.column("created_at", .double).notNull()
                table.column("updated_at", .double).notNull()
            }

            try db.create(table: "moment_record") { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("body_text", .text).notNull()
                table.column("occurred_at", .double).notNull()
                table.column("created_at", .double).notNull()
                table.column("updated_at", .double).notNull()
                table.column("mood_raw_value", .integer).notNull()
                table.column("lifecycle_state", .text).notNull()
                table.column("deleted_at", .double)
                table.column("purged_at", .double)
                table.column("revision", .integer).notNull()
            }
            try db.create(
                index: "idx_moment_record_timeline", on: "moment_record",
                columns: [
                    "lifecycle_state", "occurred_at",
                ])
            try db.create(
                index: "idx_moment_record_trash", on: "moment_record",
                columns: [
                    "lifecycle_state", "deleted_at",
                ])

            try db.create(table: "tag_record") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("created_at", .double).notNull()
                table.column("revision", .integer).notNull()
                table.uniqueKey(["name"])
            }
            try db.create(
                index: "idx_tag_record_created_at", on: "tag_record", columns: ["created_at"])

            try db.create(table: "moment_tag_link") { table in
                table.column("moment_id", .text).notNull()
                    .references("moment_record", column: "id", onDelete: .cascade)
                table.column("tag_id", .text).notNull()
                    .references("tag_record", column: "id", onDelete: .cascade)
                table.column("sort_index", .integer).notNull()
                table.column("created_at", .double).notNull()
                table.primaryKey(["moment_id", "tag_id"])
            }
            try db.create(
                index: "idx_moment_tag_link_tag", on: "moment_tag_link", columns: ["tag_id"])
            try db.create(
                index: "idx_moment_tag_link_order", on: "moment_tag_link",
                columns: [
                    "moment_id", "sort_index",
                ], unique: true)

            try db.create(table: "asset_record") { table in
                table.column("id", .text).primaryKey()
                table.column("content_hash", .text).notNull()
                table.column("mime_type", .text).notNull()
                table.column("byte_count", .integer).notNull()
                table.column("width", .integer)
                table.column("height", .integer)
                table.column("created_at", .double).notNull()
                table.column("reference_state", .text).notNull()
                table.column("pin_count", .integer).notNull()
            }
            try db.create(table: "moment_asset_link") { table in
                table.column("moment_id", .text).notNull()
                    .references("moment_record", column: "id", onDelete: .cascade)
                table.column("asset_id", .text).notNull()
                    .references("asset_record", column: "id", onDelete: .restrict)
                table.column("sort_index", .integer).notNull()
                table.column("created_at", .double).notNull()
                table.primaryKey(["moment_id", "asset_id"])
            }
            try db.create(
                index: "idx_moment_asset_link_order", on: "moment_asset_link",
                columns: [
                    "moment_id", "sort_index",
                ], unique: true)
            try db.create(
                index: "idx_moment_asset_link_asset", on: "moment_asset_link",
                columns: [
                    "asset_id"
                ])

            try db.create(table: "tombstone_record") { table in
                table.column("id", .text).primaryKey()
                table.column("entity_type", .text).notNull()
                table.column("entity_id", .text).notNull()
                table.column("operation", .text).notNull()
                table.column("created_at", .double).notNull()
                table.column("record_revision", .integer).notNull()
            }
            try db.create(
                index: "idx_tombstone_record_entity", on: "tombstone_record",
                columns: [
                    "entity_type", "entity_id",
                ])

            try db.create(table: "mutation_log") { table in
                table.column("id", .text).primaryKey()
                table.column("entity_type", .text).notNull()
                table.column("entity_id", .text).notNull()
                table.column("operation", .text).notNull()
                table.column("occurred_at", .double).notNull()
                table.column("device_id", .text).notNull()
                table.column("record_revision", .integer).notNull()
            }
            try db.create(
                index: "idx_mutation_log_entity", on: "mutation_log",
                columns: [
                    "entity_type", "entity_id", "occurred_at",
                ])

            let now = Date.now.timeIntervalSince1970
            try db.execute(
                sql: """
                    INSERT INTO library_metadata (
                        id, library_id, schema_version, device_id, sync_epoch, created_at, updated_at
                    ) VALUES (1, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    UUID().uuidString,
                    CanonicalStore.currentSchemaVersion,
                    UUID().uuidString,
                    UUID().uuidString,
                    now,
                    now,
                ]
            )
        }
        migrator.registerMigration("v2_swift_data_import_marker") { db in
            try db.execute(
                sql: "UPDATE library_metadata SET schema_version = ? WHERE id = 1",
                arguments: [CanonicalStore.currentSchemaVersion]
            )
        }
        migrator.registerMigration("v3_asset_pin_record") { db in
            try db.create(
                index: "idx_asset_record_content_hash",
                on: "asset_record",
                columns: ["content_hash"]
            )
            try db.create(table: "asset_pin_record") { table in
                table.column("id", .text).primaryKey()
                table.column("content_hash", .text).notNull()
                table.column("owner_kind", .text).notNull()
                table.column("owner_id", .text).notNull()
                table.column("created_at", .double).notNull()
                table.column("expires_at", .double)
                table.uniqueKey(["content_hash", "owner_kind", "owner_id"])
            }
            try db.create(
                index: "idx_asset_pin_record_content_hash",
                on: "asset_pin_record",
                columns: ["content_hash"]
            )
            try db.create(
                index: "idx_asset_pin_record_owner",
                on: "asset_pin_record",
                columns: ["owner_kind", "owner_id"]
            )
            try db.create(
                index: "idx_asset_pin_record_expires_at",
                on: "asset_pin_record",
                columns: ["expires_at"]
            )
            try db.execute(
                sql: "UPDATE library_metadata SET schema_version = ? WHERE id = 1",
                arguments: [CanonicalStore.currentSchemaVersion]
            )
        }
        migrator.registerMigration("v4_recovery_point_catalog") { db in
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
            try db.create(
                index: "idx_recovery_point_record_created_at",
                on: "recovery_point_record",
                columns: ["created_at"]
            )

            try db.create(table: "recovery_point_asset_record") { table in
                table.column("recovery_point_id", .text).notNull()
                    .references("recovery_point_record", column: "id", onDelete: .cascade)
                table.column("asset_id", .text).notNull()
                table.column("content_hash", .text).notNull()
                table.column("byte_count", .integer).notNull()
                table.column("relative_path", .text).notNull()
                table.primaryKey(["recovery_point_id", "asset_id"])
            }
            try db.create(
                index: "idx_recovery_point_asset_record_content_hash",
                on: "recovery_point_asset_record",
                columns: ["content_hash"]
            )
            try db.execute(
                sql: "UPDATE library_metadata SET schema_version = ? WHERE id = 1",
                arguments: [CanonicalStore.currentSchemaVersion]
            )
        }
        return migrator
    }
}

extension CanonicalStore {
    func backup(to destinationURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        let destination = try DatabaseQueue(path: destinationURL.path)
        try dbQueue.backup(to: destination)
    }
}
