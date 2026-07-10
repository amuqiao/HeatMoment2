import Foundation
import GRDB
import SwiftData
import UIKit

enum SwiftDataCanonicalImportError: Error, Equatable {
    case destinationAlreadyContainsData
    case softDeletedMomentMissingDeletedAt(UUID)
    case activeMomentHasDeletedAt(UUID)
    case invalidMoodRawValue(momentID: UUID, rawValue: Int)
    case duplicateMomentImageSortIndex(momentID: UUID, sortIndex: Int)
    case invalidImageData(UUID)
    case missingTagReference(momentID: UUID, tagID: UUID)
    case duplicateTagReference(momentID: UUID, tagID: UUID)
    case sourceBaselineMismatch(expected: String?, actual: String)
}

struct SwiftDataCanonicalImportResult: Sendable, Equatable {
    let didImport: Bool
    let tagCount: Int
    let momentCount: Int
    let assetCount: Int
    let sourceFingerprint: String?
}

@ModelActor
actor SwiftDataCanonicalImporter {
    func importIfNeeded(
        into store: CanonicalStore,
        assetStore: FileAssetStore,
        operationGate: CanonicalAssetOperationGate,
        importedAt: Date = .now
    ) throws -> SwiftDataCanonicalImportResult {
        let payload = try makePayload()
        return try operationGate.performSync {
            try importPayload(
                payload,
                into: store,
                assetStore: assetStore,
                importedAt: importedAt
            )
        }
    }

    private func importPayload(
        _ payload: ImportPayload,
        into store: CanonicalStore,
        assetStore: FileAssetStore,
        importedAt: Date
    ) throws -> SwiftDataCanonicalImportResult {
        var storedFileAssets: [StoredFileAsset] = []
        do {
            return try store.write { db in
                if try swiftDataImportedAt(db: db) != nil {
                    let storedFingerprint = try swiftDataImportSourceFingerprint(db: db)
                    guard storedFingerprint == payload.sourceFingerprint else {
                        throw SwiftDataCanonicalImportError.sourceBaselineMismatch(
                            expected: storedFingerprint,
                            actual: payload.sourceFingerprint
                        )
                    }
                    return SwiftDataCanonicalImportResult(
                        didImport: false,
                        tagCount: 0,
                        momentCount: 0,
                        assetCount: 0,
                        sourceFingerprint: storedFingerprint
                    )
                }
                try assertDestinationIsEmpty(db: db)

                for tag in payload.tags {
                    try insertTag(tag, db: db)
                }
                for moment in payload.moments {
                    try insertMoment(moment, db: db)
                    for (sortIndex, tagID) in moment.tagIDs.enumerated() {
                        try insertMomentTagLink(
                            momentID: moment.id,
                            tagID: tagID,
                            sortIndex: sortIndex,
                            createdAt: importedAt,
                            db: db
                        )
                    }
                    for asset in moment.assets {
                        let storedAsset = try assetStore.store(
                            data: asset.data,
                            expectedContentHash: asset.contentHash
                        )
                        storedFileAssets.append(storedAsset)
                        try insertAsset(asset, db: db)
                        try insertMomentAssetLink(
                            momentID: moment.id,
                            assetID: asset.id,
                            sortIndex: asset.sortIndex,
                            createdAt: importedAt,
                            db: db
                        )
                    }
                }
                try db.execute(
                    sql: """
                        UPDATE library_metadata
                        SET swift_data_imported_at = ?,
                            swift_data_import_source_fingerprint = ?,
                            updated_at = ?
                        WHERE id = 1
                        """,
                    arguments: [
                        importedAt.timeIntervalSince1970,
                        payload.sourceFingerprint,
                        importedAt.timeIntervalSince1970,
                    ]
                )
                return SwiftDataCanonicalImportResult(
                    didImport: true,
                    tagCount: payload.tags.count,
                    momentCount: payload.moments.count,
                    assetCount: payload.assetCount,
                    sourceFingerprint: payload.sourceFingerprint
                )
            }
        } catch {
            try cleanupStoredFileAssets(storedFileAssets, assetStore: assetStore)
            throw error
        }
    }

    private func makePayload() throws -> ImportPayload {
        let tagDescriptor = FetchDescriptor<Tag>(
            sortBy: [
                SortDescriptor(\.createdAt, order: .forward),
                SortDescriptor(\.name, order: .forward),
            ]
        )
        let tags = try modelContext.fetch(tagDescriptor)
            .map { tag in
                ImportedTag(id: tag.id, name: tag.name, createdAt: tag.createdAt)
            }
        let validTagIDs = Set(tags.map(\.id))

        let momentDescriptor = FetchDescriptor<Moment>(
            sortBy: [
                SortDescriptor(\.createdAt, order: .forward),
                SortDescriptor(\.occurredAt, order: .forward),
            ]
        )
        let moments = try modelContext.fetch(momentDescriptor)
            .map { moment in
                try makeImportedMoment(moment, validTagIDs: validTagIDs)
            }
        return ImportPayload(tags: tags, moments: moments)
    }

    private func makeImportedMoment(
        _ moment: Moment,
        validTagIDs: Set<UUID>
    ) throws -> ImportedMoment {
        let state: CanonicalMomentLifecycleState
        let deletedAt: Date?
        if moment.isDeleted {
            guard let sourceDeletedAt = moment.deletedAt else {
                throw SwiftDataCanonicalImportError.softDeletedMomentMissingDeletedAt(moment.id)
            }
            state = .softDeleted
            deletedAt = sourceDeletedAt
        } else {
            state = .active
            deletedAt = nil
        }

        let tagIDs = moment.tags
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map(\.id)
        var seenTagIDs = Set<UUID>()
        for tagID in tagIDs {
            guard validTagIDs.contains(tagID) else {
                throw SwiftDataCanonicalImportError.missingTagReference(
                    momentID: moment.id, tagID: tagID)
            }
            guard seenTagIDs.insert(tagID).inserted else {
                throw SwiftDataCanonicalImportError.duplicateTagReference(
                    momentID: moment.id, tagID: tagID)
            }
        }

        guard let mood = Mood(rawValue: moment.moodRawValue) else {
            throw SwiftDataCanonicalImportError.invalidMoodRawValue(
                momentID: moment.id, rawValue: moment.moodRawValue)
        }
        if !moment.isDeleted, moment.deletedAt != nil {
            throw SwiftDataCanonicalImportError.activeMomentHasDeletedAt(moment.id)
        }

        let sortedImages = moment.images
            .sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        var seenImageSortIndexes = Set<Int>()
        let assets =
            try sortedImages
            .enumerated()
            .map { offset, image in
                guard seenImageSortIndexes.insert(image.sortIndex).inserted else {
                    throw SwiftDataCanonicalImportError.duplicateMomentImageSortIndex(
                        momentID: moment.id, sortIndex: image.sortIndex)
                }
                guard let uiImage = UIImage(data: image.imageData) else {
                    throw SwiftDataCanonicalImportError.invalidImageData(image.id)
                }
                return ImportedAsset(
                    id: image.id,
                    contentHash: FileAssetStore.sha256Hex(image.imageData),
                    mimeType: "image/jpeg",
                    byteCount: image.imageData.count,
                    width: Int(uiImage.size.width.rounded()),
                    height: Int(uiImage.size.height.rounded()),
                    sortIndex: offset,
                    createdAt: image.createdAt,
                    data: image.imageData
                )
            }
        return ImportedMoment(
            id: moment.id,
            title: moment.title,
            bodyText: moment.bodyText,
            occurredAt: moment.occurredAt,
            createdAt: moment.createdAt,
            updatedAt: moment.updatedAt,
            mood: mood,
            tagIDs: tagIDs,
            lifecycleState: state,
            deletedAt: deletedAt,
            assets: assets
        )
    }

}

private struct ImportPayload: Sendable {
    let tags: [ImportedTag]
    let moments: [ImportedMoment]

    var assetCount: Int {
        moments.reduce(0) { count, moment in count + moment.assets.count }
    }

    var sourceFingerprint: String {
        var lines: [String] = ["swiftdata-baseline-v2"]
        for tag in tags {
            lines.append(
                [
                    "tag",
                    tag.id.uuidString,
                    tag.name,
                    "\(tag.createdAt.timeIntervalSince1970)",
                ].joined(separator: "\u{1f}")
            )
        }
        for moment in moments {
            lines.append(
                [
                    "moment",
                    moment.id.uuidString,
                    moment.title,
                    moment.bodyText,
                    "\(moment.occurredAt.timeIntervalSince1970)",
                    "\(moment.createdAt.timeIntervalSince1970)",
                    "\(moment.updatedAt.timeIntervalSince1970)",
                    "\(moment.mood.rawValue)",
                    moment.lifecycleState.rawValue,
                    "\(moment.deletedAt?.timeIntervalSince1970 ?? -1)",
                    moment.tagIDs.map(\.uuidString).joined(separator: ","),
                ].joined(separator: "\u{1f}")
            )
            for asset in moment.assets {
                lines.append(
                    [
                        "asset",
                        moment.id.uuidString,
                        asset.id.uuidString,
                        asset.contentHash,
                        asset.mimeType,
                        "\(asset.byteCount)",
                        "\(asset.width)",
                        "\(asset.height)",
                        "\(asset.sortIndex)",
                        "\(asset.createdAt.timeIntervalSince1970)",
                    ].joined(separator: "\u{1f}")
                )
            }
        }
        let digest = FileAssetStore.sha256Hex(Data(lines.joined(separator: "\u{1e}").utf8))
        return "swiftdata-baseline-v2|\(digest)"
    }
}

private struct ImportedTag: Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
}

private struct ImportedMoment: Sendable {
    let id: UUID
    let title: String
    let bodyText: String
    let occurredAt: Date
    let createdAt: Date
    let updatedAt: Date
    let mood: Mood
    let tagIDs: [UUID]
    let lifecycleState: CanonicalMomentLifecycleState
    let deletedAt: Date?
    let assets: [ImportedAsset]
}

private struct ImportedAsset: Sendable {
    let id: UUID
    let contentHash: String
    let mimeType: String
    let byteCount: Int
    let width: Int
    let height: Int
    let sortIndex: Int
    let createdAt: Date
    let data: Data
}

private extension SwiftDataCanonicalImporter {
    func cleanupStoredFileAssets(
        _ assets: [StoredFileAsset],
        assetStore: FileAssetStore
    ) throws {
        for asset in assets.reversed() {
            try assetStore.removeStoredAsset(asset)
        }
    }

    func swiftDataImportedAt(db: Database) throws -> Date? {
        let timestamp: Double? = try Double.fetchOne(
            db,
            sql: "SELECT swift_data_imported_at FROM library_metadata WHERE id = 1"
        )
        return timestamp.map { Date(timeIntervalSince1970: $0) }
    }

    func swiftDataImportSourceFingerprint(db: Database) throws -> String? {
        try String.fetchOne(
            db,
            sql: "SELECT swift_data_import_source_fingerprint FROM library_metadata WHERE id = 1"
        )
    }

    func assertDestinationIsEmpty(db: Database) throws {
        let tables = [
            "moment_record",
            "tag_record",
            "moment_tag_link",
            "asset_record",
            "moment_asset_link",
            "tombstone_record",
            "mutation_log",
        ]
        for table in tables {
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
            if count != 0 {
                throw SwiftDataCanonicalImportError.destinationAlreadyContainsData
            }
        }
    }

    func insertTag(_ tag: ImportedTag, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO tag_record (id, name, created_at, revision)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [
                tag.id.uuidString,
                tag.name,
                tag.createdAt.timeIntervalSince1970,
                1,
            ]
        )
    }

    func insertMoment(_ moment: ImportedMoment, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO moment_record (
                    id, title, body_text, occurred_at, created_at, updated_at,
                    mood_raw_value, lifecycle_state, deleted_at, purged_at, revision
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)
                """,
            arguments: [
                moment.id.uuidString,
                moment.title,
                moment.bodyText,
                moment.occurredAt.timeIntervalSince1970,
                moment.createdAt.timeIntervalSince1970,
                moment.updatedAt.timeIntervalSince1970,
                moment.mood.rawValue,
                moment.lifecycleState.rawValue,
                moment.deletedAt?.timeIntervalSince1970,
                1,
            ]
        )
    }

    func insertMomentTagLink(
        momentID: UUID,
        tagID: UUID,
        sortIndex: Int,
        createdAt: Date,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO moment_tag_link (moment_id, tag_id, sort_index, created_at)
                VALUES (?, ?, ?, ?)
                """,
            arguments: [
                momentID.uuidString,
                tagID.uuidString,
                sortIndex,
                createdAt.timeIntervalSince1970,
            ]
        )
    }

    func insertAsset(_ asset: ImportedAsset, db: Database) throws {
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
                asset.createdAt.timeIntervalSince1970,
                "referenced",
                0,
            ]
        )
    }

    func insertMomentAssetLink(
        momentID: UUID,
        assetID: UUID,
        sortIndex: Int,
        createdAt: Date,
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
                createdAt.timeIntervalSince1970,
            ]
        )
    }
}
