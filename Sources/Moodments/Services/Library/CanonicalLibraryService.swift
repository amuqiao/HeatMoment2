import Foundation
import Observation
import SwiftData
import UIKit

struct CanonicalMomentPreviewData: Sendable, Equatable {
    let record: CanonicalMomentRecord
    let tagNames: [String]
    let imageDatas: [CanonicalMomentImageData]

    var preferredSizesByID: [UUID: CGSize] {
        Dictionary(
            uniqueKeysWithValues: imageDatas.map { image in
                let size =
                    UIImage(data: image.data).map {
                        MomentPhotoRailLayout.itemSize(for: $0.size)
                    } ?? MomentPhotoRailLayout.fallbackItemSize
                return (image.id, size)
            }
        )
    }
}

/// Canonical store 的主流程 UI facade。
///
/// SwiftUI 层只消费这里返回的值类型和 `changeToken`，不直接持有 GRDB row、SwiftData `@Model`
/// 或 actor 内部状态。恢复点和导出仍由后续阶段切源，本类型只覆盖 M2 主流程读写。
@MainActor
@Observable
final class CanonicalLibraryService {
    let runtime: CanonicalLibraryRuntime
    private(set) var isPrepared = false
    private(set) var changeToken = 0

    var repository: CanonicalLibraryRepository { runtime.repository }

    init(runtime: CanonicalLibraryRuntime) {
        self.runtime = runtime
    }

    func prepareIfNeeded(importingFrom modelContainer: ModelContainer?) async throws {
        guard !isPrepared else { return }
        if let modelContainer {
            try await runtime.importFromSwiftDataIfNeeded(modelContainer: modelContainer)
        }
        isPrepared = true
        noteCanonicalChange()
    }

    func seedDefaultTagsIfNeeded(
        cloudKitEnabled: Bool = false,
        userDefaults: UserDefaults = .standard
    ) async throws {
        guard !userDefaults.bool(forKey: DefaultTagSeeder.hasCompletedFirstSeedKey) else { return }
        if cloudKitEnabled {
            try await Task.sleep(for: DefaultTagSeeder.firstSyncGraceTimeout)
        }
        for name in DefaultTagSeeder.defaultNames
        where try await repository.findTag(named: name) == nil {
            _ = try await repository.createOrReuseTag(name: name)
        }
        userDefaults.set(true, forKey: DefaultTagSeeder.hasCompletedFirstSeedKey)
        noteCanonicalChange()
    }

    func noteCanonicalChange() {
        changeToken += 1
    }

    func fetchTimelineEntries(filter: FilterCondition?) async throws -> [TimelineEntry] {
        let records = try await repository.fetchPage(filter: filter, offset: 0, limit: Int.max)
        let tagNamesByID = try await canonicalTagNamesByID()
        return records.map { record in
            TimelineEntry.canonical(record, tagNamesByID: tagNamesByID)
        }
    }

    func fetchFilterTags() async throws -> [TagSnapshot] {
        try await repository.fetchAllTags().map(TagSnapshot.init(canonical:))
    }

    func fetchPreviewData(id: UUID) async throws -> CanonicalMomentPreviewData {
        let record = try await repository.fetchMoment(id: id)
        let tagNamesByID = try await canonicalTagNamesByID()
        let imageDatas = try await repository.orderedImageData(momentID: id)
        return CanonicalMomentPreviewData(
            record: record,
            tagNames: record.tagIDs.compactMap { tagNamesByID[$0] },
            imageDatas: imageDatas
        )
    }

    func editingPayload(id: UUID) async throws -> MomentEditingPayload {
        let payload = try await repository.editingPayload(id: id)
        return MomentEditingPayload(
            snapshot: MomentSnapshot(canonical: payload.record),
            tagNames: payload.tagNames,
            imageDatas: payload.imageDatas
        )
    }

    func fetchTrash() async throws -> [MomentSnapshot] {
        try await repository.fetchTrash().map(MomentSnapshot.init(canonical:))
    }

    func imageData(imageID: UUID) async throws -> Data {
        try await repository.imageData(imageID: imageID)
    }

    func orderedImageData(momentID: UUID) async throws -> [CanonicalMomentImageData] {
        try await repository.orderedImageData(momentID: momentID)
    }

    func availableYears() async throws -> [Int] {
        try await repository.availableYears()
    }

    func moodByDay(year: Int, filter: FilterCondition?) async throws -> [Int: Mood] {
        try await repository.moodByDay(year: year, filter: filter)
    }

    func moodCounts(year: Int) async throws -> [Mood: Int] {
        try await repository.moodCounts(year: year)
    }

    private func canonicalTagNamesByID() async throws -> [UUID: String] {
        let tags = try await repository.fetchAllTags()
        return Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
    }
}

#if DEBUG
    extension CanonicalLibraryService {
        static func makeInMemoryForPreview() -> CanonicalLibraryService {
            do {
                return try CanonicalLibraryService(runtime: .makeInMemoryForTests())
            } catch {
                fatalError("Canonical preview 资料库初始化失败：\(error)")
            }
        }
    }
#endif

extension MomentSnapshot {
    init(canonical record: CanonicalMomentRecord) {
        id = record.id
        title = record.title
        bodyText = record.bodyText
        occurredAt = record.occurredAt
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        mood = record.mood
        tagIDs = record.tagIDs
        imageIDs = record.imageIDs
        isDeleted = record.isDeleted
        deletedAt = record.deletedAt
    }
}

extension TagSnapshot {
    init(canonical record: CanonicalTagRecord) {
        id = record.id
        name = record.name
        createdAt = record.createdAt
    }
}

extension TimelineEntry {
    static func canonical(
        _ record: CanonicalMomentRecord,
        tagNamesByID: [UUID: String]
    ) -> TimelineEntry {
        TimelineEntry(
            id: record.id,
            momentID: record.id,
            kind: .real,
            title: record.title,
            bodyText: record.bodyText,
            mood: record.mood,
            occurredAt: record.occurredAt,
            tagNames: record.tagIDs.compactMap { tagNamesByID[$0] },
            placeholderImageHexColors: [],
            imageIDs: record.imageIDs
        )
    }
}
