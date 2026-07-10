import GRDB
import SwiftData
import UIKit
import XCTest
@testable import Moodments

final class CanonicalRuntimeImportTests: XCTestCase {
    func testRuntimeCreatesCanonicalStoreAtDescriptorPath() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let descriptor = CanonicalStoreDescriptor(rootDirectory: directory)
        let runtime = try CanonicalLibraryRuntime(descriptor: descriptor)
        let metadata = try await runtime.repository.metadata()

        XCTAssertEqual(metadata.schemaVersion, CanonicalStore.currentSchemaVersion)
        XCTAssertTrue(FileManager.default.fileExists(atPath: descriptor.databaseURL.path))
    }

    func testImportsSwiftDataBaselineAndMarksCompletion() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let source = try makeSwiftDataSource(in: container)
        let runtime = try CanonicalLibraryRuntime.makeInMemoryForTests()
        let importedAt = Date(timeIntervalSince1970: 1_000)

        let result = try await runtime.importFromSwiftDataIfNeeded(
            modelContainer: container,
            importedAt: importedAt
        )

        XCTAssertTrue(result.didImport)
        XCTAssertEqual(result.tagCount, 2)
        XCTAssertEqual(result.momentCount, 2)
        XCTAssertEqual(result.assetCount, 2)
        let sourceFingerprint = try XCTUnwrap(result.sourceFingerprint)
        XCTAssertTrue(sourceFingerprint.hasPrefix("swiftdata-baseline-v1|"))
        let metadata = try await runtime.repository.metadata()
        XCTAssertEqual(metadata.swiftDataImportedAt, importedAt)
        XCTAssertEqual(metadata.swiftDataImportSourceFingerprint, sourceFingerprint)

        let tags = try await runtime.repository.fetchAllTags()
        XCTAssertEqual(tags.map(\.id), [source.workTagID, source.lifeTagID])
        XCTAssertEqual(tags.map(\.name), ["工作", "生活"])

        let page = try await runtime.repository.fetchPage()
        XCTAssertEqual(page.map(\.id), [source.activeMomentID])
        XCTAssertEqual(page.first?.title, "有照片")
        XCTAssertEqual(page.first?.bodyText, "正文")
        XCTAssertEqual(page.first?.mood, .happy)
        XCTAssertEqual(page.first?.tagIDs, [source.workTagID, source.lifeTagID])
        XCTAssertEqual(page.first?.lifecycleState, .active)

        let trash = try await runtime.repository.fetchTrash()
        XCTAssertEqual(trash.map(\.id), [source.deletedMomentID])
        XCTAssertEqual(trash.first?.lifecycleState, .softDeleted)
        XCTAssertEqual(trash.first?.deletedAt, Date(timeIntervalSince1970: 700))

        let mutationLog = try await runtime.repository.fetchMutationLog()
        XCTAssertTrue(mutationLog.isEmpty)
        let assetRows = try runtime.store.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT asset_record.id, asset_record.byte_count, asset_record.width,
                        asset_record.height, moment_asset_link.sort_index
                    FROM asset_record
                    INNER JOIN moment_asset_link ON moment_asset_link.asset_id = asset_record.id
                    WHERE moment_asset_link.moment_id = ?
                    ORDER BY moment_asset_link.sort_index ASC
                    """,
                arguments: [source.activeMomentID.uuidString]
            )
        }
        XCTAssertEqual(assetRows.map { $0["id"] as String }, source.imageIDs.map(\.uuidString))
        XCTAssertEqual(assetRows.map { $0["sort_index"] as Int }, [0, 1])
        XCTAssertEqual(
            assetRows.map { $0["byte_count"] as Int },
            [source.imageByteCount, source.imageByteCount])
        XCTAssertEqual(assetRows.map { $0["width"] as Int }, [4, 4])
        XCTAssertEqual(assetRows.map { $0["height"] as Int }, [4, 4])

        let secondResult = try await runtime.importFromSwiftDataIfNeeded(
            modelContainer: container,
            importedAt: Date(timeIntervalSince1970: 2_000)
        )
        XCTAssertFalse(secondResult.didImport)
        XCTAssertEqual(secondResult.tagCount, 0)
        XCTAssertEqual(secondResult.momentCount, 0)
        XCTAssertEqual(secondResult.assetCount, 0)
        XCTAssertEqual(secondResult.sourceFingerprint, sourceFingerprint)
        let metadataAfterSecondRun = try await runtime.repository.metadata()
        XCTAssertEqual(metadataAfterSecondRun.swiftDataImportedAt, importedAt)
        XCTAssertEqual(metadataAfterSecondRun.swiftDataImportSourceFingerprint, sourceFingerprint)

        let context = ModelContext(container)
        context.insert(Tag(name: "导入后新增"))
        try context.save()
        do {
            _ = try await runtime.importFromSwiftDataIfNeeded(
                modelContainer: container,
                importedAt: Date(timeIntervalSince1970: 3_000)
            )
            XCTFail("期望 source provenance 不一致时拒绝跳过导入")
        } catch SwiftDataCanonicalImportError.sourceBaselineMismatch(
            let expected,
            let actual
        ) {
            XCTAssertEqual(expected, sourceFingerprint)
            XCTAssertNotEqual(actual, sourceFingerprint)
        } catch {
            XCTFail("期望 sourceBaselineMismatch，实际抛出 \(error)")
        }
    }

    func testImportRollsBackWhenSourceMomentIsInvalid() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let context = ModelContext(container)
        let invalidMomentID = UUID()
        context.insert(
            Moment(
                id: invalidMomentID,
                title: "坏数据",
                isDeleted: true,
                deletedAt: nil
            )
        )
        try context.save()
        let runtime = try CanonicalLibraryRuntime.makeInMemoryForTests()

        do {
            _ = try await runtime.importFromSwiftDataIfNeeded(modelContainer: container)
            XCTFail("期望软删除缺少 deletedAt 时导入失败")
        } catch SwiftDataCanonicalImportError.softDeletedMomentMissingDeletedAt(let id) {
            XCTAssertEqual(id, invalidMomentID)
        } catch {
            XCTFail("期望 SwiftDataCanonicalImportError，实际抛出 \(error)")
        }

        let metadata = try await runtime.repository.metadata()
        XCTAssertNil(metadata.swiftDataImportedAt)
        let totalMomentCount = try await runtime.repository.totalMomentCount()
        XCTAssertEqual(totalMomentCount, 0)
        let tags = try await runtime.repository.fetchAllTags()
        XCTAssertTrue(tags.isEmpty)
    }

    func testImportFailsWhenCanonicalDestinationAlreadyContainsData() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let runtime = try CanonicalLibraryRuntime.makeInMemoryForTests()
        _ = try await runtime.repository.createOrReuseTag(name: "已有标签")

        do {
            _ = try await runtime.importFromSwiftDataIfNeeded(modelContainer: container)
            XCTFail("期望非空 Canonical 目标库拒绝 baseline 导入")
        } catch SwiftDataCanonicalImportError.destinationAlreadyContainsData {
        } catch {
            XCTFail("期望 destinationAlreadyContainsData，实际抛出 \(error)")
        }

        let metadata = try await runtime.repository.metadata()
        XCTAssertNil(metadata.swiftDataImportedAt)
        let tags = try await runtime.repository.fetchAllTags()
        XCTAssertEqual(tags.map(\.name), ["已有标签"])
    }

    func testImportFailsWhenCanonicalDestinationOnlyContainsHistory() async throws {
        let container = try ModelContainerConfig.makeInMemoryContainer()
        let runtime = try CanonicalLibraryRuntime.makeInMemoryForTests()
        let tag = try await runtime.repository.createOrReuseTag(name: "临时标签")
        try await runtime.repository.deleteTag(id: tag.id)
        let tags = try await runtime.repository.fetchAllTags()
        XCTAssertTrue(tags.isEmpty)

        do {
            _ = try await runtime.importFromSwiftDataIfNeeded(modelContainer: container)
            XCTFail("期望只有 mutation/tombstone 历史时也拒绝 baseline 导入")
        } catch SwiftDataCanonicalImportError.destinationAlreadyContainsData {
        } catch {
            XCTFail("期望 destinationAlreadyContainsData，实际抛出 \(error)")
        }
    }

    private func makeSwiftDataSource(in container: ModelContainer) throws -> SwiftDataSourceFixture
    {
        let context = ModelContext(container)
        let workTagID = UUID()
        let lifeTagID = UUID()
        let workTag = Tag(
            id: workTagID,
            name: "工作",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let lifeTag = Tag(
            id: lifeTagID,
            name: "生活",
            createdAt: Date(timeIntervalSince1970: 200)
        )
        context.insert(workTag)
        context.insert(lifeTag)

        let activeMomentID = UUID()
        let activeMoment = Moment(
            id: activeMomentID,
            title: "有照片",
            bodyText: "正文",
            occurredAt: Date(timeIntervalSince1970: 500),
            createdAt: Date(timeIntervalSince1970: 300),
            updatedAt: Date(timeIntervalSince1970: 400),
            mood: .happy,
            tags: [lifeTag, workTag]
        )
        context.insert(activeMoment)

        let imageData = Self.makeImageData()
        let firstImageID = UUID()
        let secondImageID = UUID()
        let secondImage = MomentImage(
            id: secondImageID,
            sortIndex: 20,
            createdAt: Date(timeIntervalSince1970: 620),
            imageData: imageData,
            moment: activeMoment
        )
        let firstImage = MomentImage(
            id: firstImageID,
            sortIndex: 10,
            createdAt: Date(timeIntervalSince1970: 610),
            imageData: imageData,
            moment: activeMoment
        )
        context.insert(secondImage)
        context.insert(firstImage)
        activeMoment.images = [secondImage, firstImage]

        let deletedMomentID = UUID()
        context.insert(
            Moment(
                id: deletedMomentID,
                title: "垃圾箱",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 450),
                createdAt: Date(timeIntervalSince1970: 250),
                updatedAt: Date(timeIntervalSince1970: 700),
                mood: .sad,
                isDeleted: true,
                deletedAt: Date(timeIntervalSince1970: 700)
            )
        )
        try context.save()

        return SwiftDataSourceFixture(
            workTagID: workTagID,
            lifeTagID: lifeTagID,
            activeMomentID: activeMomentID,
            deletedMomentID: deletedMomentID,
            imageIDs: [firstImageID, secondImageID],
            imageByteCount: imageData.count
        )
    }

    private static func makeImageData() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format)
        let image = renderer.image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            preconditionFailure("测试图片编码失败")
        }
        return data
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CanonicalRuntimeImportTests-\(UUID().uuidString)", isDirectory: true)
        return directory
    }
}

private struct SwiftDataSourceFixture {
    let workTagID: UUID
    let lifeTagID: UUID
    let activeMomentID: UUID
    let deletedMomentID: UUID
    let imageIDs: [UUID]
    let imageByteCount: Int
}
