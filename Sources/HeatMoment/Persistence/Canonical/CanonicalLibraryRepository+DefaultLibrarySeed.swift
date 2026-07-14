import Foundation
import GRDB

extension CanonicalLibraryRepository {
    @discardableResult
    func seedDefaultLibraryIfNeeded(
        tagNames: [String],
        moments: [CanonicalDefaultLibrarySeedMoment],
        seedVersion: Int,
        now: Date = .now
    ) throws -> Bool {
        try store.write { db in
            guard try currentDefaultSeedVersion(db: db) < seedVersion else { return false }
            guard try isEmptyLibraryForDefaultSeed(db: db) else {
                try markDefaultLibrarySeeded(seedVersion: seedVersion, now: now, db: db)
                return false
            }

            var tagIDsByName: [String: UUID] = [:]
            for (index, name) in tagNames.enumerated() {
                let tagID: UUID
                if let existing = try fetchTag(named: name, db: db) {
                    tagID = existing.id
                } else {
                    tagID = UUID()
                    try insertSeedTag(
                        id: tagID,
                        name: name,
                        createdAt: now.addingTimeInterval(Double(index)),
                        mutationTime: now,
                        db: db
                    )
                }
                tagIDsByName[name] = tagID
            }

            try insertSeedMoments(
                moments,
                tagIDsByName: tagIDsByName,
                now: now,
                db: db
            )
            try markDefaultLibrarySeeded(seedVersion: seedVersion, now: now, db: db)
            return true
        }
    }

    private func currentDefaultSeedVersion(db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT default_seed_version FROM library_metadata WHERE id = 1"
        ) ?? 0
    }

    private func isEmptyLibraryForDefaultSeed(db: Database) throws -> Bool {
        let existingMomentCount =
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM moment_record
                    WHERE lifecycle_state NOT IN (?, ?)
                    """,
                arguments: [
                    CanonicalMomentLifecycleState.purgePending.rawValue,
                    CanonicalMomentLifecycleState.purged.rawValue
                ]
            ) ?? 0
        let existingTagCount = try totalTagCount(db: db)
        return existingMomentCount == 0 && existingTagCount == 0
    }

    private func insertSeedTag(
        id: UUID,
        name: String,
        createdAt: Date,
        mutationTime: Date,
        db: Database
    ) throws {
        let revision = 1
        try db.execute(
            sql: """
                INSERT INTO tag_record (id, name, created_at, revision)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [
                id.uuidString,
                name,
                createdAt.timeIntervalSince1970,
                revision
            ]
        )
        try insertMutation(
            entityType: "tag",
            entityID: id,
            operation: "create",
            recordRevision: revision,
            now: mutationTime,
            db: db
        )
    }

    private func insertSeedMoments(
        _ moments: [CanonicalDefaultLibrarySeedMoment],
        tagIDsByName: [String: UUID],
        now: Date,
        db: Database
    ) throws {
        for moment in moments {
            guard let tagID = tagIDsByName[moment.tagName] else {
                throw DatabaseError(message: "Missing default tag: \(moment.tagName)")
            }
            let momentID = UUID()
            let revision = 1
            try db.execute(
                sql: """
                    INSERT INTO moment_record (
                        id, title, body_text, occurred_at, created_at, updated_at,
                        mood_raw_value, lifecycle_state, deleted_at, purged_at, revision
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?)
                    """,
                arguments: [
                    momentID.uuidString,
                    moment.title,
                    moment.bodyText,
                    moment.occurredAt.timeIntervalSince1970,
                    now.timeIntervalSince1970,
                    now.timeIntervalSince1970,
                    moment.mood.rawValue,
                    CanonicalMomentLifecycleState.active.rawValue,
                    revision
                ]
            )
            try replaceTagLinks(momentID: momentID, tagIDs: [tagID], now: now, db: db)
            try insertMutation(
                entityType: "moment",
                entityID: momentID,
                operation: "create",
                recordRevision: revision,
                now: now,
                db: db
            )
        }
    }

    func markDefaultLibrarySeeded(seedVersion: Int, now: Date, db: Database) throws {
        try db.execute(
            sql: """
                UPDATE library_metadata
                SET default_seed_version = ?, updated_at = ?
                WHERE id = 1
                """,
            arguments: [seedVersion, now.timeIntervalSince1970]
        )
    }

    func totalTagCount(db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tag_record") ?? 0
    }
}
