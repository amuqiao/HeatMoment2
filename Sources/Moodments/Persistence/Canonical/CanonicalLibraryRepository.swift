import Foundation
import GRDB

actor CanonicalLibraryRepository {
    private let store: CanonicalStore

    init(store: CanonicalStore) {
        self.store = store
    }

    func metadata() throws -> CanonicalLibraryMetadata {
        try store.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM library_metadata WHERE id = 1")
            else {
                throw DatabaseError(message: "Missing library metadata")
            }
            return try CanonicalLibraryMetadata(
                libraryID: row.canonicalUUID("library_id"),
                schemaVersion: row["schema_version"],
                deviceID: row.canonicalUUID("device_id"),
                syncEpoch: row.canonicalUUID("sync_epoch"),
                createdAt: row.canonicalDate("created_at"),
                updatedAt: row.canonicalDate("updated_at")
            )
        }
    }

    @discardableResult
    func createMoment(
        title: String,
        bodyText: String,
        occurredAt: Date,
        mood: Mood,
        tagIDs: [UUID] = [],
        now: Date = .now
    ) throws -> UUID {
        try store.write { db in
            try ensureTagsExist(tagIDs, db: db)
            let id = UUID()
            let revision = 1
            try db.execute(
                sql: """
                    INSERT INTO moment_record (
                        id, title, body_text, occurred_at, created_at, updated_at,
                        mood_raw_value, lifecycle_state, deleted_at, purged_at, revision
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?)
                    """,
                arguments: [
                    id.uuidString,
                    title,
                    bodyText,
                    occurredAt.timeIntervalSince1970,
                    now.timeIntervalSince1970,
                    now.timeIntervalSince1970,
                    mood.rawValue,
                    CanonicalMomentLifecycleState.active.rawValue,
                    revision,
                ]
            )
            try replaceTagLinks(momentID: id, tagIDs: tagIDs, now: now, db: db)
            try insertMutation(
                entityType: "moment",
                entityID: id,
                operation: "create",
                recordRevision: revision,
                now: now,
                db: db
            )
            return id
        }
    }

    func updateMoment(
        id: UUID,
        title: String? = nil,
        bodyText: String? = nil,
        occurredAt: Date? = nil,
        mood: Mood? = nil,
        tagIDs: [UUID]? = nil,
        now: Date = .now
    ) throws {
        try store.write { db in
            var record = try fetchMomentRecord(id: id, db: db)
            if record.isTerminalDeletion {
                throw RepositoryError.momentNotFound(id)
            }
            if let tagIDs {
                try ensureTagsExist(tagIDs, db: db)
            }

            record = CanonicalMomentRecord(
                id: record.id,
                title: title ?? record.title,
                bodyText: bodyText ?? record.bodyText,
                occurredAt: occurredAt ?? record.occurredAt,
                createdAt: record.createdAt,
                updatedAt: now,
                mood: mood ?? record.mood,
                tagIDs: tagIDs ?? record.tagIDs,
                lifecycleState: record.lifecycleState,
                deletedAt: record.deletedAt,
                purgedAt: record.purgedAt,
                revision: record.revision + 1
            )
            try db.execute(
                sql: """
                    UPDATE moment_record
                    SET title = ?, body_text = ?, occurred_at = ?, updated_at = ?,
                        mood_raw_value = ?, revision = ?
                    WHERE id = ?
                    """,
                arguments: [
                    record.title,
                    record.bodyText,
                    record.occurredAt.timeIntervalSince1970,
                    record.updatedAt.timeIntervalSince1970,
                    record.mood.rawValue,
                    record.revision,
                    id.uuidString,
                ]
            )
            if let tagIDs {
                try replaceTagLinks(momentID: id, tagIDs: tagIDs, now: now, db: db)
            }
            try insertMutation(
                entityType: "moment",
                entityID: id,
                operation: "update",
                recordRevision: record.revision,
                now: now,
                db: db
            )
        }
    }

    func softDeleteMoment(id: UUID, now: Date = .now) throws {
        try setMomentLifecycle(
            id: id,
            state: .softDeleted,
            deletedAt: now,
            purgedAt: nil,
            operation: "softDelete",
            now: now
        )
    }

    func restoreMoment(id: UUID, now: Date = .now) throws {
        try setMomentLifecycle(
            id: id,
            state: .active,
            deletedAt: nil,
            purgedAt: nil,
            operation: "restore",
            now: now
        )
    }

    func purgeMoment(id: UUID, now: Date = .now) throws {
        try setMomentLifecycle(
            id: id,
            state: .purgePending,
            deletedAt: nil,
            purgedAt: nil,
            operation: "purge",
            now: now
        )
    }

    func fetchPurgePendingMoments() throws -> [CanonicalMomentRecord] {
        try store.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM moment_record
                    WHERE lifecycle_state = ?
                    ORDER BY updated_at ASC
                    """,
                arguments: [CanonicalMomentLifecycleState.purgePending.rawValue]
            )
            return try rows.map { try makeMomentRecord(row: $0, db: db) }
        }
    }

    func fetchPage(offset: Int = 0, limit: Int = 50) throws -> [CanonicalMomentRecord] {
        try store.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM moment_record
                    WHERE lifecycle_state = ?
                    ORDER BY occurred_at DESC
                    LIMIT ? OFFSET ?
                    """,
                arguments: [CanonicalMomentLifecycleState.active.rawValue, limit, offset]
            )
            return try rows.map { try makeMomentRecord(row: $0, db: db) }
        }
    }

    func fetchTrash() throws -> [CanonicalMomentRecord] {
        try store.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM moment_record
                    WHERE lifecycle_state = ?
                    ORDER BY deleted_at DESC
                    """,
                arguments: [CanonicalMomentLifecycleState.softDeleted.rawValue]
            )
            return try rows.map { try makeMomentRecord(row: $0, db: db) }
        }
    }

    func totalMomentCount() throws -> Int {
        try store.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM moment_record
                    WHERE lifecycle_state NOT IN (?, ?)
                    """,
                arguments: [
                    CanonicalMomentLifecycleState.purgePending.rawValue,
                    CanonicalMomentLifecycleState.purged.rawValue,
                ]
            ) ?? 0
        }
    }

    func createOrReuseTag(name: String, quotaService: QuotaService? = nil, now: Date = .now) throws
        -> TagCreateOrReuseResult
    {
        try store.write { db in
            if let existing = try fetchTag(named: name, db: db) {
                return TagCreateOrReuseResult(
                    id: existing.id, name: existing.name, didCreate: false)
            }
            if let quotaService {
                switch quotaService.checkCanCreateTag(currentTagCount: try totalTagCount(db: db)) {
                case .allowed:
                    break
                case .exceeded(let kind):
                    throw RepositoryError.quotaExceeded(kind)
                }
            }

            let id = UUID()
            let revision = 1
            try db.execute(
                sql: """
                    INSERT INTO tag_record (id, name, created_at, revision)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [id.uuidString, name, now.timeIntervalSince1970, revision]
            )
            try insertMutation(
                entityType: "tag",
                entityID: id,
                operation: "create",
                recordRevision: revision,
                now: now,
                db: db
            )
            return TagCreateOrReuseResult(id: id, name: name, didCreate: true)
        }
    }

    func renameTag(id: UUID, newName: String, now: Date = .now) throws {
        try store.write { db in
            let tag = try fetchTag(id: id, db: db)
            if let existing = try fetchTag(named: newName, db: db), existing.id != id {
                throw RepositoryError.tagNameConflict(newName)
            }
            let revision = tag.revision + 1
            try db.execute(
                sql: "UPDATE tag_record SET name = ?, revision = ? WHERE id = ?",
                arguments: [newName, revision, id.uuidString]
            )
            try insertMutation(
                entityType: "tag",
                entityID: id,
                operation: "rename",
                recordRevision: revision,
                now: now,
                db: db
            )
        }
    }

    func deleteTag(id: UUID, now: Date = .now) throws {
        try store.write { db in
            let tag = try fetchTag(id: id, db: db)
            let affectedMomentRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT moment_record.id, moment_record.revision
                    FROM moment_record
                    INNER JOIN moment_tag_link ON moment_tag_link.moment_id = moment_record.id
                    WHERE moment_tag_link.tag_id = ?
                        AND moment_record.lifecycle_state NOT IN (?, ?)
                    ORDER BY moment_record.occurred_at DESC
                    """,
                arguments: [
                    id.uuidString,
                    CanonicalMomentLifecycleState.purgePending.rawValue,
                    CanonicalMomentLifecycleState.purged.rawValue,
                ]
            )
            try db.execute(sql: "DELETE FROM tag_record WHERE id = ?", arguments: [id.uuidString])
            for row in affectedMomentRows {
                let momentID = try row.canonicalUUID("id")
                let currentRevision: Int = row["revision"]
                let revision = currentRevision + 1
                try db.execute(
                    sql: """
                        UPDATE moment_record
                        SET updated_at = ?, revision = ?
                        WHERE id = ?
                        """,
                    arguments: [now.timeIntervalSince1970, revision, momentID.uuidString]
                )
                try insertMutation(
                    entityType: "moment",
                    entityID: momentID,
                    operation: "tagDetach",
                    recordRevision: revision,
                    now: now,
                    db: db
                )
            }
            try insertMutation(
                entityType: "tag",
                entityID: id,
                operation: "delete",
                recordRevision: tag.revision + 1,
                now: now,
                db: db
            )
            try insertTombstone(
                entityType: "tag",
                entityID: id,
                operation: "delete",
                recordRevision: tag.revision + 1,
                now: now,
                db: db
            )
        }
    }

    func fetchAllTags() throws -> [CanonicalTagRecord] {
        try store.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM tag_record ORDER BY created_at ASC")
                .map(makeTagRecord(row:))
        }
    }

    func totalTagCount() throws -> Int {
        try store.read { db in
            try totalTagCount(db: db)
        }
    }

    func fetchMutationLog() throws -> [CanonicalMutationRecord] {
        try store.read { db in
            try Row.fetchAll(
                db, sql: "SELECT * FROM mutation_log ORDER BY occurred_at ASC, rowid ASC"
            )
            .map(makeMutationRecord(row:))
        }
    }
}

private extension CanonicalLibraryRepository {
    private func setMomentLifecycle(
        id: UUID,
        state: CanonicalMomentLifecycleState,
        deletedAt: Date?,
        purgedAt: Date?,
        operation: String,
        now: Date
    ) throws {
        try store.write { db in
            let record = try fetchMomentRecord(id: id, db: db)
            if record.isTerminalDeletion {
                throw RepositoryError.momentNotFound(id)
            }
            let revision = record.revision + 1
            try db.execute(
                sql: """
                    UPDATE moment_record
                    SET lifecycle_state = ?, deleted_at = ?, purged_at = ?, updated_at = ?, revision = ?
                    WHERE id = ?
                    """,
                arguments: [
                    state.rawValue,
                    deletedAt?.timeIntervalSince1970,
                    purgedAt?.timeIntervalSince1970,
                    now.timeIntervalSince1970,
                    revision,
                    id.uuidString,
                ]
            )
            try insertMutation(
                entityType: "moment",
                entityID: id,
                operation: operation,
                recordRevision: revision,
                now: now,
                db: db
            )
            if state == .purgePending || state == .purged {
                try insertTombstone(
                    entityType: "moment",
                    entityID: id,
                    operation: operation,
                    recordRevision: revision,
                    now: now,
                    db: db
                )
            }
        }
    }

    private func fetchMomentRecord(id: UUID, db: Database) throws -> CanonicalMomentRecord {
        guard
            let row = try Row.fetchOne(
                db, sql: "SELECT * FROM moment_record WHERE id = ?", arguments: [id.uuidString])
        else {
            throw RepositoryError.momentNotFound(id)
        }
        return try makeMomentRecord(row: row, db: db)
    }

    private func makeMomentRecord(row: Row, db: Database) throws -> CanonicalMomentRecord {
        let moodRawValue: Int = row["mood_raw_value"]
        let stateRawValue: String = row["lifecycle_state"]
        guard let mood = Mood(rawValue: moodRawValue) else {
            throw DatabaseError(message: "Invalid mood raw value: \(moodRawValue)")
        }
        guard let state = CanonicalMomentLifecycleState(rawValue: stateRawValue) else {
            throw DatabaseError(message: "Invalid moment lifecycle state: \(stateRawValue)")
        }
        let id = try row.canonicalUUID("id")
        let tagIDs = try String.fetchAll(
            db,
            sql: "SELECT tag_id FROM moment_tag_link WHERE moment_id = ? ORDER BY sort_index ASC",
            arguments: [id.uuidString]
        ).map { try UUID(canonicalString: $0) }
        return CanonicalMomentRecord(
            id: id,
            title: row["title"],
            bodyText: row["body_text"],
            occurredAt: row.canonicalDate("occurred_at"),
            createdAt: row.canonicalDate("created_at"),
            updatedAt: row.canonicalDate("updated_at"),
            mood: mood,
            tagIDs: tagIDs,
            lifecycleState: state,
            deletedAt: row.canonicalOptionalDate("deleted_at"),
            purgedAt: row.canonicalOptionalDate("purged_at"),
            revision: row["revision"]
        )
    }

    private func fetchTag(id: UUID, db: Database) throws -> CanonicalTagRecord {
        guard
            let row = try Row.fetchOne(
                db, sql: "SELECT * FROM tag_record WHERE id = ?", arguments: [id.uuidString])
        else {
            throw RepositoryError.tagNotFound(id)
        }
        return try makeTagRecord(row: row)
    }

    private func fetchTag(named name: String, db: Database) throws -> CanonicalTagRecord? {
        try Row.fetchOne(db, sql: "SELECT * FROM tag_record WHERE name = ?", arguments: [name])
            .map(makeTagRecord(row:))
    }

    private func makeTagRecord(row: Row) throws -> CanonicalTagRecord {
        try CanonicalTagRecord(
            id: row.canonicalUUID("id"),
            name: row["name"],
            createdAt: row.canonicalDate("created_at"),
            revision: row["revision"]
        )
    }

    private func makeMutationRecord(row: Row) throws -> CanonicalMutationRecord {
        try CanonicalMutationRecord(
            id: row.canonicalUUID("id"),
            entityType: row["entity_type"],
            entityID: row.canonicalUUID("entity_id"),
            operation: row["operation"],
            occurredAt: row.canonicalDate("occurred_at"),
            deviceID: row.canonicalUUID("device_id"),
            recordRevision: row["record_revision"]
        )
    }

    private func ensureTagsExist(_ ids: [UUID], db: Database) throws {
        for id in ids {
            _ = try fetchTag(id: id, db: db)
        }
    }

    private func replaceTagLinks(momentID: UUID, tagIDs: [UUID], now: Date, db: Database) throws {
        try db.execute(
            sql: "DELETE FROM moment_tag_link WHERE moment_id = ?", arguments: [momentID.uuidString]
        )
        for (sortIndex, tagID) in tagIDs.enumerated() {
            try db.execute(
                sql: """
                    INSERT INTO moment_tag_link (moment_id, tag_id, sort_index, created_at)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [
                    momentID.uuidString, tagID.uuidString, sortIndex, now.timeIntervalSince1970,
                ]
            )
        }
    }

    private func totalTagCount(db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tag_record") ?? 0
    }

    private func insertMutation(
        entityType: String,
        entityID: UUID,
        operation: String,
        recordRevision: Int,
        now: Date,
        db: Database
    ) throws {
        let metadata = try metadata(db: db)
        try db.execute(
            sql: """
                INSERT INTO mutation_log (
                    id, entity_type, entity_id, operation, occurred_at, device_id, record_revision
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                UUID().uuidString,
                entityType,
                entityID.uuidString,
                operation,
                now.timeIntervalSince1970,
                metadata.deviceID.uuidString,
                recordRevision,
            ]
        )
    }

    private func insertTombstone(
        entityType: String,
        entityID: UUID,
        operation: String,
        recordRevision: Int,
        now: Date,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO tombstone_record (
                    id, entity_type, entity_id, operation, created_at, record_revision
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                UUID().uuidString,
                entityType,
                entityID.uuidString,
                operation,
                now.timeIntervalSince1970,
                recordRevision,
            ]
        )
    }

    private func metadata(db: Database) throws -> CanonicalLibraryMetadata {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM library_metadata WHERE id = 1")
        else {
            throw DatabaseError(message: "Missing library metadata")
        }
        return try CanonicalLibraryMetadata(
            libraryID: row.canonicalUUID("library_id"),
            schemaVersion: row["schema_version"],
            deviceID: row.canonicalUUID("device_id"),
            syncEpoch: row.canonicalUUID("sync_epoch"),
            createdAt: row.canonicalDate("created_at"),
            updatedAt: row.canonicalDate("updated_at")
        )
    }
}
