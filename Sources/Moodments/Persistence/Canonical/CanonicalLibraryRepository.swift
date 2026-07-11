import Foundation
import GRDB

actor CanonicalLibraryRepository {
    private let store: CanonicalStore
    private let assetStore: FileAssetStore?
    private let operationGate: CanonicalAssetOperationGate?

    init(
        store: CanonicalStore,
        assetStore: FileAssetStore? = nil,
        operationGate: CanonicalAssetOperationGate? = nil
    ) {
        self.store = store
        self.assetStore = assetStore
        self.operationGate = operationGate
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
}

extension CanonicalLibraryRepository {
    @discardableResult
    func createMoment(
        title: String,
        bodyText: String,
        occurredAt: Date,
        mood: Mood,
        tagIDs: [UUID] = [],
        imageDatas: [Data] = [],
        now: Date = .now
    ) throws -> UUID {
        try performAssetMutation(imageDatas: imageDatas) { preparedAssets in
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
                try replaceAssetLinks(
                    momentID: id,
                    preparedAssets: preparedAssets,
                    now: now,
                    db: db
                )
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
    }

    func updateMoment(
        id: UUID,
        title: String? = nil,
        bodyText: String? = nil,
        occurredAt: Date? = nil,
        mood: Mood? = nil,
        tagIDs: [UUID]? = nil,
        imageDatas: [Data]? = nil,
        now: Date = .now
    ) throws {
        try performAssetMutation(imageDatas: imageDatas ?? []) { preparedAssets in
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
                    imageIDs: record.imageIDs,
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
                if imageDatas != nil {
                    try replaceAssetLinks(
                        momentID: id,
                        preparedAssets: preparedAssets,
                        now: now,
                        db: db
                    )
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
        try fetchPage(filter: nil, offset: offset, limit: limit)
    }

    func exportPayload(
        startAtInclusive: Date? = nil,
        endAtExclusive: Date? = nil,
        includePhotos: Bool = true
    ) throws -> [CanonicalMomentExportPayload] {
        try store.read { db in
            var dateClause = ""
            var arguments: StatementArguments = [
                CanonicalMomentLifecycleState.active.rawValue
            ]
            if let startAtInclusive {
                dateClause += " AND occurred_at >= ?"
                arguments += [startAtInclusive.timeIntervalSince1970]
            }
            if let endAtExclusive {
                dateClause += " AND occurred_at < ?"
                arguments += [endAtExclusive.timeIntervalSince1970]
            }
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM moment_record
                    WHERE lifecycle_state = ?
                    \(dateClause)
                    ORDER BY occurred_at DESC, id DESC
                    """,
                arguments: arguments
            )
            return try rows.map { row in
                let record = try makeMomentRecord(row: row, db: db)
                let tagNamesByID = try tagNamesByID(ids: record.tagIDs, db: db)
                let imageDatas = includePhotos
                    ? try orderedImageData(momentID: record.id, db: db)
                    : []
                return CanonicalMomentExportPayload(
                    record: record,
                    tagNames: record.tagIDs.compactMap { tagNamesByID[$0] },
                    imageDatas: imageDatas
                )
            }
        }
    }

    func fetchPage(
        filter: FilterCondition?,
        offset: Int = 0,
        limit: Int = 50
    ) throws -> [CanonicalMomentRecord] {
        try store.read { db in
            var arguments: StatementArguments = [
                CanonicalMomentLifecycleState.active.rawValue
            ]
            var moodClause = ""
            if let mood = filter?.mood {
                moodClause = "AND mood_raw_value = ?"
                arguments += [mood.rawValue]
            }
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM moment_record
                    WHERE lifecycle_state = ?
                        \(moodClause)
                    ORDER BY occurred_at DESC
                    """,
                arguments: arguments
            )
            return
                try rows
                .map { try makeMomentRecord(row: $0, db: db) }
                .filter { record in
                    filter.map { $0.matches(tagIDs: Set(record.tagIDs), mood: record.mood) } ?? true
                }
                .dropFirst(offset)
                .prefix(limit)
                .map { $0 }
        }
    }

    func fetchMoment(id: UUID) throws -> CanonicalMomentRecord {
        try store.read { db in
            try fetchReadableMomentRecord(id: id, db: db)
        }
    }

    func editingPayload(id: UUID) throws -> CanonicalMomentEditingPayload {
        try store.read { db in
            let record = try fetchReadableMomentRecord(id: id, db: db)
            let tagNames = try tagNamesByID(ids: record.tagIDs, db: db)
            let imageDatas = try orderedImageData(momentID: id, db: db).map(\.data)
            return CanonicalMomentEditingPayload(
                record: record,
                tagNames: tagNames,
                imageDatas: imageDatas
            )
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

    func imageCount(momentID: UUID) throws -> Int {
        try store.read { db in
            _ = try fetchReadableMomentRecord(id: momentID, db: db)
            return try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM moment_asset_link WHERE moment_id = ?",
                arguments: [momentID.uuidString]
            ) ?? 0
        }
    }

    func imageData(imageID: UUID) throws -> Data {
        try store.read { db in
            let record = try fetchAssetRecord(id: imageID, db: db)
            return try requiredAssetStore().data(forContentHash: record.contentHash)
        }
    }

    func orderedImageData(momentID: UUID) throws -> [CanonicalMomentImageData] {
        try store.read { db in
            _ = try fetchReadableMomentRecord(id: momentID, db: db)
            return try orderedImageData(momentID: momentID, db: db)
        }
    }

    func availableYears(
        includingCurrentYear currentYear: Int = HeatmapYearRange.currentYear
    ) throws -> [Int] {
        try store.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT occurred_at FROM moment_record
                    WHERE lifecycle_state = ?
                    ORDER BY occurred_at ASC
                    """,
                arguments: [CanonicalMomentLifecycleState.active.rawValue]
            )
            let calendar = Calendar.current
            var years = Set<Int>()
            years.insert(currentYear)
            for row in rows {
                years.insert(calendar.component(.year, from: row.canonicalDate("occurred_at")))
            }
            return years.sorted()
        }
    }

    func moodByDay(year: Int, filter: FilterCondition?) throws -> [Int: Mood] {
        let interval = Self.yearInterval(year: year)
        return try store.read { db in
            var arguments: StatementArguments = [
                CanonicalMomentLifecycleState.active.rawValue,
                interval.start.timeIntervalSince1970,
                interval.end.timeIntervalSince1970,
            ]
            var moodClause = ""
            if let mood = filter?.mood {
                moodClause = "AND mood_raw_value = ?"
                arguments += [mood.rawValue]
            }
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM moment_record
                    WHERE lifecycle_state = ?
                        AND occurred_at >= ?
                        AND occurred_at < ?
                        \(moodClause)
                    ORDER BY occurred_at ASC
                    """,
                arguments: arguments
            )
            let calendar = Calendar.current
            var result: [Int: Mood] = [:]
            for row in rows {
                let record = try makeMomentRecord(row: row, db: db)
                if let filter, !filter.matches(tagIDs: Set(record.tagIDs), mood: record.mood) {
                    continue
                }
                guard
                    let dayOfYear = calendar.ordinality(
                        of: .day,
                        in: .year,
                        for: record.occurredAt
                    )
                else {
                    assertionFailure("年内记录 dayOfYear 计算失败：\(record.occurredAt)")
                    continue
                }
                result[dayOfYear] = record.mood
            }
            return result
        }
    }

    func moodCounts(year: Int) throws -> [Mood: Int] {
        let interval = Self.yearInterval(year: year)
        return try store.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT mood_raw_value FROM moment_record
                    WHERE lifecycle_state = ?
                        AND occurred_at >= ?
                        AND occurred_at < ?
                    """,
                arguments: [
                    CanonicalMomentLifecycleState.active.rawValue,
                    interval.start.timeIntervalSince1970,
                    interval.end.timeIntervalSince1970,
                ]
            )
            var counts: [Mood: Int] = [:]
            for row in rows {
                let moodRawValue: Int = row["mood_raw_value"]
                guard let mood = Mood(rawValue: moodRawValue) else {
                    throw DatabaseError(message: "Invalid mood raw value: \(moodRawValue)")
                }
                counts[mood, default: 0] += 1
            }
            return counts
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

    func findTag(named name: String) throws -> CanonicalTagRecord? {
        try store.read { db in
            try fetchTag(named: name, db: db)
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
    func performAssetMutation<Value>(
        imageDatas: [Data],
        operation: ([PreparedAsset]) throws -> Value
    ) throws -> Value {
        guard !imageDatas.isEmpty else {
            return try operation([])
        }
        let assetStore = try requiredAssetStore()
        let operationGate = try requiredOperationGate()
        var preparedAssets: [PreparedAsset] = []
        return try operationGate.performSync {
            do {
                preparedAssets = try imageDatas.map { data in
                    let storedAsset = try assetStore.store(data: data)
                    let dimensions = Self.imageDimensions(data: data)
                    return PreparedAsset(
                        id: UUID(),
                        contentHash: storedAsset.contentHash,
                        mimeType: Self.mimeType(data: data),
                        byteCount: storedAsset.byteCount,
                        width: dimensions.width,
                        height: dimensions.height,
                        storedFileAsset: storedAsset
                    )
                }
                return try operation(preparedAssets)
            } catch {
                try cleanupStoredFileAssets(preparedAssets.map(\.storedFileAsset))
                throw error
            }
        }
    }

    func requiredAssetStore() throws -> FileAssetStore {
        guard let assetStore else {
            throw RepositoryError.assetStoreUnavailable
        }
        return assetStore
    }

    func requiredOperationGate() throws -> CanonicalAssetOperationGate {
        guard let operationGate else {
            throw RepositoryError.assetStoreUnavailable
        }
        return operationGate
    }

    func cleanupStoredFileAssets(_ assets: [StoredFileAsset]) throws {
        guard let assetStore else { return }
        for asset in assets.reversed() {
            try assetStore.removeStoredAsset(asset)
        }
    }

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

    private func fetchReadableMomentRecord(id: UUID, db: Database) throws -> CanonicalMomentRecord {
        let record = try fetchMomentRecord(id: id, db: db)
        if record.isTerminalDeletion {
            throw RepositoryError.momentNotFound(id)
        }
        return record
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
        let imageIDs = try String.fetchAll(
            db,
            sql: """
                SELECT asset_id FROM moment_asset_link
                WHERE moment_id = ?
                ORDER BY sort_index ASC
                """,
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
            imageIDs: imageIDs,
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

    func replaceAssetLinks(
        momentID: UUID,
        preparedAssets: [PreparedAsset],
        now: Date,
        db: Database
    ) throws {
        let oldAssetIDs = try String.fetchAll(
            db,
            sql: "SELECT asset_id FROM moment_asset_link WHERE moment_id = ?",
            arguments: [momentID.uuidString]
        )
        try db.execute(
            sql: "DELETE FROM moment_asset_link WHERE moment_id = ?",
            arguments: [momentID.uuidString]
        )
        try finalizeUnlinkedAssetRecords(assetIDs: oldAssetIDs, db: db)

        for (sortIndex, asset) in preparedAssets.enumerated() {
            try insertAsset(asset, now: now, db: db)
            try db.execute(
                sql: """
                    INSERT INTO moment_asset_link (moment_id, asset_id, sort_index, created_at)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [
                    momentID.uuidString,
                    asset.id.uuidString,
                    sortIndex,
                    now.timeIntervalSince1970,
                ]
            )
        }
    }

    func insertAsset(_ asset: PreparedAsset, now: Date, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO asset_record (
                    id, content_hash, mime_type, byte_count, width, height, created_at,
                    reference_state, pin_count
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                asset.id.uuidString,
                asset.contentHash,
                asset.mimeType,
                asset.byteCount,
                asset.width,
                asset.height,
                now.timeIntervalSince1970,
                "referenced",
                0,
            ]
        )
    }

    func finalizeUnlinkedAssetRecords(assetIDs: [String], db: Database) throws {
        for assetID in assetIDs {
            let linkedCount =
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM moment_asset_link WHERE asset_id = ?",
                    arguments: [assetID]
                ) ?? 0
            let pinCount =
                try Int.fetchOne(
                    db,
                    sql: "SELECT pin_count FROM asset_record WHERE id = ?",
                    arguments: [assetID]
                ) ?? 0
            if linkedCount == 0 && pinCount == 0 {
                try db.execute(
                    sql: "DELETE FROM asset_record WHERE id = ?",
                    arguments: [assetID]
                )
            }
        }
    }

    func fetchAssetRecord(id: UUID, db: Database) throws -> AssetRecord {
        guard
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT asset_record.content_hash
                    FROM asset_record
                    INNER JOIN moment_asset_link
                        ON moment_asset_link.asset_id = asset_record.id
                    INNER JOIN moment_record
                        ON moment_record.id = moment_asset_link.moment_id
                    WHERE asset_record.id = ?
                        AND moment_record.lifecycle_state NOT IN (?, ?)
                    LIMIT 1
                    """,
                arguments: [
                    id.uuidString,
                    CanonicalMomentLifecycleState.purgePending.rawValue,
                    CanonicalMomentLifecycleState.purged.rawValue,
                ]
            )
        else {
            throw RepositoryError.momentImageNotFound(id)
        }
        return AssetRecord(contentHash: row["content_hash"])
    }

    func orderedImageData(momentID: UUID, db: Database) throws -> [CanonicalMomentImageData] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT asset_record.id, asset_record.content_hash
                FROM moment_asset_link
                INNER JOIN asset_record ON asset_record.id = moment_asset_link.asset_id
                WHERE moment_asset_link.moment_id = ?
                ORDER BY moment_asset_link.sort_index ASC
                """,
            arguments: [momentID.uuidString]
        )
        let assetStore = try requiredAssetStore()
        return try rows.map { row in
            let id = try row.canonicalUUID("id")
            let contentHash: String = row["content_hash"]
            return try CanonicalMomentImageData(
                id: id,
                data: assetStore.data(forContentHash: contentHash)
            )
        }
    }

    func tagNamesByID(ids: [UUID], db: Database) throws -> [UUID: String] {
        var result: [UUID: String] = [:]
        for id in ids {
            result[id] = try fetchTag(id: id, db: db).name
        }
        return result
    }

    private func totalTagCount(db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tag_record") ?? 0
    }

}
