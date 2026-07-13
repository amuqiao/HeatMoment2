import CoreGraphics
import GRDB
import PDFKit
import UIKit
import XCTest
@testable import HeatMoment

final class LocalDataClosureAcceptanceTests: XCTestCase {
    private var rootDirectory: URL!
    private var outputRootURL: URL!

    override func setUpWithError() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "LocalDataClosureAcceptanceTests-\(UUID().uuidString)",
                isDirectory: true
            )
        rootDirectory = baseDirectory.appendingPathComponent("Canonical", isDirectory: true)
        outputRootURL = baseDirectory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let rootDirectory {
            try FileManager.default.removeItem(at: rootDirectory.deletingLastPathComponent())
        }
        rootDirectory = nil
        outputRootURL = nil
    }

    @MainActor
    func testCanonicalLocalDataClosureRestoresAndExportsOnlyActiveMoments() async throws {
        let descriptor = CanonicalStoreDescriptor(rootDirectory: rootDirectory)
        let restoredMomentID = try await Self.preparePendingRestore(descriptor: descriptor)

        let bootResult = try CanonicalBootRestoreGate.performPendingRestoreIfNeeded(
            descriptor: descriptor,
            now: Date(timeIntervalSince1970: 500)
        )
        XCTAssertNotNil(bootResult.restoredContext)

        let restoredRuntime = try CanonicalLibraryRuntime(descriptor: descriptor)
        let restoredActiveTitles = try await Self.activeTitles(in: restoredRuntime.repository)
        let restoredTrash = try await restoredRuntime.repository.fetchTrash()
        XCTAssertEqual(restoredActiveTitles, ["恢复点活跃"])
        XCTAssertTrue(restoredTrash.isEmpty)

        try await restoredRuntime.repository.softDeleteMoment(
            id: restoredMomentID,
            now: Date(timeIntervalSince1970: 520)
        )
        let softDeletedTrashTitles = try await restoredRuntime.repository.fetchTrash().map(\.title)
        XCTAssertEqual(
            softDeletedTrashTitles,
            ["恢复点活跃"]
        )
        let softDeletedSnapshot = try await CanonicalExportSnapshotStore(
            repository: restoredRuntime.repository
        )
        .makeSnapshot(
            request: ExportRequest(
                scope: .all,
                format: .markdown,
                includePhotos: true,
                requestedAt: Date(timeIntervalSince1970: 510)
            )
        )
        XCTAssertTrue(softDeletedSnapshot.moments.isEmpty)

        try await restoredRuntime.repository.restoreMoment(
            id: restoredMomentID,
            now: Date(timeIntervalSince1970: 600)
        )
        let trashAfterRestore = try await restoredRuntime.repository.fetchTrash()
        XCTAssertTrue(trashAfterRestore.isEmpty)

        let purgedID = try await restoredRuntime.repository.createMoment(
            title: "彻底删除候选",
            bodyText: "",
            occurredAt: Date(timeIntervalSince1970: 700),
            mood: .sad,
            tagIDs: [],
            imageDatas: []
        )
        try await restoredRuntime.repository.purgeMoment(
            id: purgedID,
            now: Date(timeIntervalSince1970: 710)
        )
        let purgePendingTitles = try await restoredRuntime.repository.fetchPurgePendingMoments()
            .map(\.title)
        XCTAssertEqual(
            purgePendingTitles,
            ["彻底删除候选"]
        )
        let activeTitlesAfterPurge = try await Self.activeTitles(in: restoredRuntime.repository)
        XCTAssertEqual(activeTitlesAfterPurge, ["恢复点活跃"])

        let recoveryCoordinator = CanonicalRecoveryCoordinator(
            runtime: restoredRuntime,
            appVersion: "1.0.8"
        )
        let syncStatusService = SyncStatusService(cloudKitEnabled: true)
        let boundaryBeforeExport = try await Self.exportBoundarySnapshot(
            runtime: restoredRuntime,
            coordinator: recoveryCoordinator,
            syncStatusService: syncStatusService
        )

        let markdownResult = try await Self.export(
            format: .markdown,
            repository: restoredRuntime.repository,
            outputRootURL: outputRootURL,
            now: Date(timeIntervalSince1970: 800)
        )
        XCTAssertEqual(markdownResult.momentCount, 1)
        XCTAssertEqual(markdownResult.assetCount, 1)
        try Self.assertMarkdownContainsOnlyRestoredMoment(markdownResult)

        let pdfResult = try await Self.export(
            format: .pdf,
            repository: restoredRuntime.repository,
            outputRootURL: outputRootURL,
            now: Date(timeIntervalSince1970: 900)
        )
        XCTAssertEqual(pdfResult.momentCount, 1)
        XCTAssertEqual(pdfResult.assetCount, 1)
        try Self.assertPDFContainsOnlyRestoredMoment(pdfResult)

        let boundaryAfterExport = try await Self.exportBoundarySnapshot(
            runtime: restoredRuntime,
            coordinator: recoveryCoordinator,
            syncStatusService: syncStatusService
        )
        XCTAssertEqual(boundaryAfterExport, boundaryBeforeExport)
    }

    @MainActor
    private static func preparePendingRestore(
        descriptor: CanonicalStoreDescriptor
    ) async throws -> UUID {
        let selectedID = uuid("00000000-0000-0000-0000-000000007001")
        let secondID = uuid("00000000-0000-0000-0000-000000007002")
        let thirdID = uuid("00000000-0000-0000-0000-000000007003")
        let restoreSafetyID = uuid("00000000-0000-0000-0000-000000007004")
        let restoreJobID = uuid("00000000-0000-0000-0000-000000007005")
        let restoredSyncEpoch = uuid("00000000-0000-0000-0000-000000007006")

        do {
            let runtime = try CanonicalLibraryRuntime(descriptor: descriptor)
            let coordinator = CanonicalRecoveryCoordinator(
                runtime: runtime,
                appVersion: "1.0.8"
            )
            let tag = try await runtime.repository.createOrReuseTag(name: "闭环")
            let restoredMomentID = try await runtime.repository.createMoment(
                title: "恢复点活跃",
                bodyText: "应在恢复后继续可读、可导出。",
                occurredAt: Date(timeIntervalSince1970: 100),
                mood: .happy,
                tagIDs: [tag.id],
                imageDatas: [Self.makeJPEGData()]
            )
            let selected = try await coordinator.createRecoveryPoint(
                id: selectedID,
                createdAt: Date(timeIntervalSince1970: 200)
            )

            _ = try await runtime.repository.createMoment(
                title: "恢复前当前数据",
                bodyText: "",
                occurredAt: Date(timeIntervalSince1970: 300),
                mood: .normal
            )
            _ = try await coordinator.createRecoveryPoint(
                id: secondID,
                createdAt: Date(timeIntervalSince1970: 300)
            )
            try await runtime.repository.softDeleteMoment(
                id: restoredMomentID,
                now: Date(timeIntervalSince1970: 350)
            )
            _ = try await coordinator.createRecoveryPoint(
                id: thirdID,
                createdAt: Date(timeIntervalSince1970: 400)
            )
            let recoveryPointIDs = try await coordinator.listRecoveryPoints().map(\.id)
            XCTAssertEqual(
                recoveryPointIDs,
                [thirdID, secondID, selectedID]
            )

            let prepared = try await coordinator.prepareRestore(
                id: selected.id,
                restoreJobID: restoreJobID,
                restoredSyncEpoch: restoredSyncEpoch,
                restoreSafetyID: restoreSafetyID,
                now: Date(timeIntervalSince1970: 450)
            )
            XCTAssertEqual(prepared.selectedRecoveryPoint.id, selectedID)
            XCTAssertEqual(
                prepared.retentionStatus,
                .completed(evictedRecoveryPointIDs: [selectedID])
            )
            let recoveryPointCountAfterPrepare = try await coordinator.listRecoveryPoints().count
            XCTAssertEqual(recoveryPointCountAfterPrepare, 3)
            return restoredMomentID
        }
    }

    private static func export(
        format: ExportFormat,
        repository: CanonicalLibraryRepository,
        outputRootURL: URL,
        now: Date
    ) async throws -> ExportResult {
        let service = ExportService(
            snapshotProvider: CanonicalExportSnapshotStore(repository: repository),
            outputRootURL: outputRootURL,
            markdownRenderer: MarkdownExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!),
            pdfRenderer: PDFExportRenderer(timeZone: TimeZone(secondsFromGMT: 0)!)
        )
        return try await service.exportAll(format: format, now: now)
    }

    private static func activeTitles(
        in repository: CanonicalLibraryRepository
    ) async throws -> [String] {
        try await repository.fetchPage(offset: 0, limit: 10).map(\.title)
    }

    private static func assertMarkdownContainsOnlyRestoredMoment(
        _ result: ExportResult
    ) throws {
        let markdown = try String(contentsOf: result.fileURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("## 恢复点活跃"))
        XCTAssertTrue(markdown.contains("- 标签：#闭环"))
        XCTAssertTrue(markdown.contains("![照片 1](assets/"))
        XCTAssertFalse(markdown.contains("恢复前当前数据"))
        XCTAssertFalse(markdown.contains("彻底删除候选"))
    }

    private static func assertPDFContainsOnlyRestoredMoment(_ result: ExportResult) throws {
        let pdfData = try Data(contentsOf: result.fileURL)
        XCTAssertTrue(pdfData.starts(with: Data("%PDF".utf8)))
        let provider = try XCTUnwrap(CGDataProvider(data: pdfData as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertGreaterThanOrEqual(document.numberOfPages, 1)
        let pdfText = try XCTUnwrap(PDFDocument(data: pdfData)?.string)
        XCTAssertTrue(pdfText.contains("恢复点活跃"))
        XCTAssertFalse(pdfText.contains("恢复前当前数据"))
        XCTAssertFalse(pdfText.contains("彻底删除候选"))
    }

    @MainActor
    private static func exportBoundarySnapshot(
        runtime: CanonicalLibraryRuntime,
        coordinator: CanonicalRecoveryCoordinator,
        syncStatusService: SyncStatusService
    ) async throws -> ExportBoundarySnapshot {
        ExportBoundarySnapshot(
            momentCount: try await runtime.repository.totalMomentCount(),
            usedTagCount: try usedTagCount(in: runtime.store),
            recoveryPointIDs: try await coordinator.listRecoveryPoints().map(\.id),
            syncStatus: syncStatusService.status
        )
    }

    private static func usedTagCount(in store: CanonicalStore) throws -> Int {
        try store.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT tag_id) FROM moment_tag_link") ?? 0
        }
    }

    private static func makeJPEGData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 14))
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 14))
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 4, y: 3, width: 12, height: 8))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }

    private static func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}

private struct ExportBoundarySnapshot: Equatable {
    let momentCount: Int
    let usedTagCount: Int
    let recoveryPointIDs: [UUID]
    let syncStatus: SyncStatus
}

private extension CanonicalBootRestoreResult {
    var restoredContext: CanonicalPendingRestoreContext? {
        guard case .restored(let context) = self else { return nil }
        return context
    }
}
