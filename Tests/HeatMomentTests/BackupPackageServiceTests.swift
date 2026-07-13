import XCTest
@testable import HeatMoment

final class BackupPackageServiceTests: XCTestCase {
    func testPrepareExportPackageWritesInspectableCompletePackage() async throws {
        let fixture = try makeFixture()
        try await seedMoment(in: fixture.runtime, imageData: Data([0xFF, 0xD8, 0x01]))
        let service = CanonicalBackupPackageService(
            runtime: fixture.runtime,
            appVersion: "1.0-test",
            exportHistoryStore: BackupPackageExportHistoryStore(
                key: "BackupPackageServiceTests-\(UUID().uuidString)"
            )
        )
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

        let result = try await service.prepareExportPackage(createdAt: createdAt)
        let preview = try await service.inspectPackage(at: result.fileURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.preparedDirectory.path))
        XCTAssertEqual(result.createdAt, createdAt)
        XCTAssertEqual(result.counts.recordCount, 1)
        XCTAssertEqual(result.counts.assetCount, 1)
        XCTAssertEqual(preview.id, result.packageID)
        XCTAssertEqual(preview.sourceAppVersion, "1.0-test")
        XCTAssertEqual(preview.counts, result.counts)
        XCTAssertEqual(preview.manifest.restoreSemantics.mode, "fullReplacement")
        XCTAssertEqual(preview.manifest.payloads.filter { $0.role == .sqlite }.count, 1)
        XCTAssertEqual(preview.manifest.payloads.filter { $0.role == .assetBlob }.count, 1)
    }

    func testPrepareExportPackageDoesNotRecordLastExportedAt() async throws {
        let fixture = try makeFixture()
        try await seedMoment(in: fixture.runtime, imageData: Data([0x01, 0x02]))
        let historyStore = BackupPackageExportHistoryStore(
            key: "BackupPackageServiceTests-\(UUID().uuidString)"
        )
        let service = CanonicalBackupPackageService(
            runtime: fixture.runtime,
            appVersion: "1.0-test",
            exportHistoryStore: historyStore
        )

        _ = try await service.prepareExportPackage(
            createdAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let summary = try await service.currentSummary()

        XCTAssertNil(summary.lastExportedAt)
    }

    func testCompletePreparedExportRecordsHistoryAndCleansTemporaryPackage() async throws {
        let fixture = try makeFixture()
        try await seedMoment(in: fixture.runtime, imageData: Data([0x03, 0x04]))
        let historyStore = BackupPackageExportHistoryStore(
            key: "BackupPackageServiceTests-\(UUID().uuidString)"
        )
        let service = CanonicalBackupPackageService(
            runtime: fixture.runtime,
            appVersion: "1.0-test",
            exportHistoryStore: historyStore
        )
        let prepared = try await service.prepareExportPackage(
            createdAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let completedAt = Date(timeIntervalSince1970: 1_700_000_300)

        let completion = try await service.completePreparedExport(
            prepared,
            completedAt: completedAt
        )
        let summary = try await service.currentSummary()

        XCTAssertEqual(completion.packageID, prepared.packageID)
        XCTAssertEqual(completion.exportedAt, completedAt)
        XCTAssertEqual(completion.cleanupStatus, .completed)
        XCTAssertEqual(summary.lastExportedAt, completedAt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.preparedDirectory.path))
    }

    func testCompletePreparedExportReportsCleanupFailureAfterRecordingHistory() async throws {
        let fixture = try makeFixture()
        try await seedMoment(in: fixture.runtime, imageData: Data([0x09, 0x0A]))
        let historyStore = BackupPackageExportHistoryStore(
            key: "BackupPackageServiceTests-\(UUID().uuidString)"
        )
        let service = CanonicalBackupPackageService(
            runtime: fixture.runtime,
            appVersion: "1.0-test",
            exportHistoryStore: historyStore,
            removePreparedExportDirectory: { _ in
                throw InjectedCleanupError.failed
            }
        )
        let prepared = try await service.prepareExportPackage(
            createdAt: Date(timeIntervalSince1970: 1_700_000_350)
        )
        let completedAt = Date(timeIntervalSince1970: 1_700_000_360)

        let completion = try await service.completePreparedExport(
            prepared,
            completedAt: completedAt
        )
        let summary = try await service.currentSummary()

        XCTAssertEqual(summary.lastExportedAt, completedAt)
        XCTAssertEqual(
            completion.cleanupStatus,
            .failedAfterExportRecorded(String(describing: InjectedCleanupError.failed))
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.preparedDirectory.path))
    }

    func testDiscardPreparedExportDoesNotRecordHistoryAndCleansTemporaryPackage() async throws {
        let fixture = try makeFixture()
        try await seedMoment(in: fixture.runtime, imageData: Data([0x05, 0x06]))
        let historyStore = BackupPackageExportHistoryStore(
            key: "BackupPackageServiceTests-\(UUID().uuidString)"
        )
        let service = CanonicalBackupPackageService(
            runtime: fixture.runtime,
            appVersion: "1.0-test",
            exportHistoryStore: historyStore
        )
        let prepared = try await service.prepareExportPackage(
            createdAt: Date(timeIntervalSince1970: 1_700_000_400)
        )

        try await service.discardPreparedExport(prepared)
        let summary = try await service.currentSummary()

        XCTAssertNil(summary.lastExportedAt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.preparedDirectory.path))
    }

    func testCurrentSummaryDoesNotDiscardActivePreparedExport() async throws {
        let fixture = try makeFixture()
        try await seedMoment(in: fixture.runtime, imageData: Data([0x07, 0x08]))
        let historyStore = BackupPackageExportHistoryStore(
            key: "BackupPackageServiceTests-\(UUID().uuidString)"
        )
        let service = CanonicalBackupPackageService(
            runtime: fixture.runtime,
            appVersion: "1.0-test",
            exportHistoryStore: historyStore
        )
        let prepared = try await service.prepareExportPackage(
            createdAt: Date(timeIntervalSince1970: 1_700_000_500)
        )

        let summary = try await service.currentSummary()

        XCTAssertNil(summary.lastExportedAt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.preparedDirectory.path))
    }

    func testDiscardAbandonedPreparedExportsCleansTemporaryPackage() async throws {
        let fixture = try makeFixture()
        try await seedMoment(in: fixture.runtime, imageData: Data([0x0B, 0x0C]))
        let historyStore = BackupPackageExportHistoryStore(
            key: "BackupPackageServiceTests-\(UUID().uuidString)"
        )
        let service = CanonicalBackupPackageService(
            runtime: fixture.runtime,
            appVersion: "1.0-test",
            exportHistoryStore: historyStore
        )
        let prepared = try await service.prepareExportPackage(
            createdAt: Date(timeIntervalSince1970: 1_700_000_600)
        )

        try await service.discardAbandonedPreparedExports()
        let summary = try await service.currentSummary()

        XCTAssertNil(summary.lastExportedAt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.preparedDirectory.path))
    }

    func testInspectRejectsPackageWithTrailingData() async throws {
        let fixture = try makeFixture()
        try await seedMoment(in: fixture.runtime, imageData: Data([0x10, 0x11]))
        let service = CanonicalBackupPackageService(
            runtime: fixture.runtime,
            appVersion: "1.0-test",
            exportHistoryStore: BackupPackageExportHistoryStore(
                key: "BackupPackageServiceTests-\(UUID().uuidString)"
            )
        )
        let result = try await service.prepareExportPackage(
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        let handle = try FileHandle(forWritingTo: result.fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0x99]))
        try handle.close()

        do {
            _ = try await service.inspectPackage(at: result.fileURL)
            XCTFail("篡改后的备份包不应通过校验")
        } catch BackupPackageError.unexpectedTrailingData {
        }
    }

    func testInspectRejectsPackageWithPayloadHashMismatchAndCleansStaging() async throws {
        let fixture = try makeFixture()
        try await seedMoment(
            in: fixture.runtime,
            title: "待篡改备份内容",
            imageData: Data([0x12, 0x13, 0x14])
        )
        let service = CanonicalBackupPackageService(
            runtime: fixture.runtime,
            appVersion: "1.0-test",
            exportHistoryStore: BackupPackageExportHistoryStore(
                key: "BackupPackageServiceTests-\(UUID().uuidString)"
            )
        )
        let result = try await service.prepareExportPackage(
            createdAt: Date(timeIntervalSince1970: 2_500)
        )
        try corruptLastByte(in: result.fileURL)

        do {
            _ = try await service.inspectPackage(at: result.fileURL)
            XCTFail("payload 被篡改后不应通过校验")
        } catch BackupPackageError.payloadHashMismatch {
        }
        XCTAssertTrue(try importRootIsEmpty(descriptor: fixture.descriptor))
    }

    func testPrepareImportStagesPendingRestoreAndImportsAssets() async throws {
        let source = try makeFixture()
        let target = try makeFixture()
        let imageData = Data([0x20, 0x21, 0x22])
        try await seedMoment(in: source.runtime, imageData: imageData)
        let sourceService = CanonicalBackupPackageService(
            runtime: source.runtime,
            appVersion: "1.0-test",
            exportHistoryStore: BackupPackageExportHistoryStore(
                key: "BackupPackageServiceTests-\(UUID().uuidString)"
            )
        )
        let targetService = CanonicalBackupPackageService(
            runtime: target.runtime,
            appVersion: "1.0-test",
            exportHistoryStore: BackupPackageExportHistoryStore(
                key: "BackupPackageServiceTests-\(UUID().uuidString)"
            )
        )
        let exported = try await sourceService.prepareExportPackage(
            createdAt: Date(timeIntervalSince1970: 3_000)
        )
        let preview = try await targetService.inspectPackage(at: exported.fileURL)

        let prepared = try await targetService.prepareImport(
            preview,
            now: Date(timeIntervalSince1970: 4_000)
        )

        XCTAssertEqual(prepared.packageID, exported.packageID)
        XCTAssertEqual(prepared.pendingContext.selectedRecoveryPointID, exported.packageID)
        XCTAssertEqual(prepared.retentionStatus, .completed)
        XCTAssertNotNil(prepared.pendingContext.restoreSafetyPointID)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: target.descriptor.pendingRestoreDirectory
                    .appendingPathComponent("armed")
                    .path
            )
        )
        let contentHash = FileAssetStore.sha256Hex(imageData)
        let storedAsset = try target.runtime.assetStore.validateStoredAsset(
            forContentHash: contentHash
        )
        XCTAssertEqual(storedAsset.byteCount, imageData.count)
        XCTAssertTrue(try importRootIsEmpty(descriptor: target.descriptor))
    }

    func testPrepareImportReturnsRetentionFailureAfterRestoreIsArmed() async throws {
        let source = try makeFixture()
        let target = try makeFixture()
        try await seedMoment(in: source.runtime, imageData: Data([0x30, 0x31]))
        let sourceService = CanonicalBackupPackageService(
            runtime: source.runtime,
            appVersion: "1.0-test",
            exportHistoryStore: BackupPackageExportHistoryStore(
                key: "BackupPackageServiceTests-\(UUID().uuidString)"
            )
        )
        let targetService = CanonicalBackupPackageService(
            runtime: target.runtime,
            appVersion: "1.0-test",
            exportHistoryStore: BackupPackageExportHistoryStore(
                key: "BackupPackageServiceTests-\(UUID().uuidString)"
            ),
            enforceRecoveryPointRetention: { _ in
                throw InjectedRetentionError.failed
            }
        )
        let exported = try await sourceService.prepareExportPackage(
            createdAt: Date(timeIntervalSince1970: 4_500)
        )
        let preview = try await targetService.inspectPackage(at: exported.fileURL)

        let prepared = try await targetService.prepareImport(
            preview,
            now: Date(timeIntervalSince1970: 4_600)
        )

        XCTAssertEqual(
            prepared.retentionStatus,
            .failedAfterRestoreArmed(String(describing: InjectedRetentionError.failed))
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: target.descriptor.pendingRestoreDirectory
                    .appendingPathComponent("armed")
                    .path
            )
        )
    }

    func testPreparedImportRestoresCompletePackageOnNextLaunch() async throws {
        let source = try makeFixture()
        let target = makeDescriptorFixture()
        let sourceImageData = Data([0x40, 0x41, 0x42])
        try await seedMoment(
            in: source.runtime,
            title: "备份包里的时刻",
            imageData: sourceImageData
        )
        let exported = try await CanonicalBackupPackageService(
            runtime: source.runtime,
            appVersion: "1.0-test",
            exportHistoryStore: BackupPackageExportHistoryStore(
                key: "BackupPackageServiceTests-\(UUID().uuidString)"
            )
        )
        .prepareExportPackage(createdAt: Date(timeIntervalSince1970: 5_000))
        var prepared: BackupPackagePreparedImport?

        do {
            let targetRuntime = try CanonicalLibraryRuntime(descriptor: target.descriptor)
            try await seedMoment(
                in: targetRuntime,
                title: "导入前目标库时刻",
                imageData: Data([0x50, 0x51])
            )
            let targetService = CanonicalBackupPackageService(
                runtime: targetRuntime,
                appVersion: "1.0-test",
                exportHistoryStore: BackupPackageExportHistoryStore(
                    key: "BackupPackageServiceTests-\(UUID().uuidString)"
                )
            )
            let preview = try await targetService.inspectPackage(at: exported.fileURL)
            prepared = try await targetService.prepareImport(
                preview,
                now: Date(timeIntervalSince1970: 5_100)
            )
        }

        let result = try CanonicalBootRestoreGate.performPendingRestoreIfNeeded(
            descriptor: target.descriptor,
            now: Date(timeIntervalSince1970: 5_200)
        )
        let restoredRuntime = try CanonicalLibraryRuntime(descriptor: target.descriptor)
        let moments = try await restoredRuntime.repository.fetchPage(offset: 0, limit: 10)

        XCTAssertEqual(
            BackupBootRestoreResult(result: result),
            .restored(try XCTUnwrap(prepared).pendingContext)
        )
        XCTAssertEqual(moments.map(\.title), ["备份包里的时刻"])
        let restoredMoment = try XCTUnwrap(moments.first)
        let imageID = try XCTUnwrap(restoredMoment.imageIDs.first)
        let restoredImageData = try await restoredRuntime.repository.imageData(imageID: imageID)
        XCTAssertEqual(restoredImageData, sourceImageData)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: target.descriptor.pendingRestoreDirectory.path
            )
        )
        let safetyPointID = try XCTUnwrap(prepared?.pendingContext.restoreSafetyPointID)
        XCTAssertNotNil(try restoredRuntime.recoveryPointStore.recoveryPoint(id: safetyPointID))
    }
}

private extension BackupPackageServiceTests {
    enum InjectedCleanupError: Error, Equatable {
        case failed
    }

    enum InjectedRetentionError: Error, Equatable {
        case failed
    }

    struct Fixture {
        let rootDirectory: URL
        let descriptor: CanonicalStoreDescriptor
        let runtime: CanonicalLibraryRuntime
    }

    struct DescriptorFixture {
        let rootDirectory: URL
        let descriptor: CanonicalStoreDescriptor
    }

    func makeFixture() throws -> Fixture {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BackupPackageServiceTests-\(UUID().uuidString)",
                isDirectory: true
            )
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: rootDirectory.path) {
                try FileManager.default.removeItem(at: rootDirectory)
            }
        }
        let descriptor = CanonicalStoreDescriptor(rootDirectory: rootDirectory)
        return try Fixture(
            rootDirectory: rootDirectory,
            descriptor: descriptor,
            runtime: CanonicalLibraryRuntime(descriptor: descriptor)
        )
    }

    func makeDescriptorFixture() -> DescriptorFixture {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BackupPackageServiceTests-\(UUID().uuidString)",
                isDirectory: true
            )
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: rootDirectory.path) {
                try FileManager.default.removeItem(at: rootDirectory)
            }
        }
        let descriptor = CanonicalStoreDescriptor(rootDirectory: rootDirectory)
        return DescriptorFixture(rootDirectory: rootDirectory, descriptor: descriptor)
    }

    func seedMoment(
        in runtime: CanonicalLibraryRuntime,
        title: String = "备份测试",
        imageData: Data
    ) async throws {
        try await runtime.repository.createMoment(
            title: title,
            bodyText: "完整备份包测试内容",
            occurredAt: Date(timeIntervalSince1970: 1_000),
            mood: .happy,
            imageDatas: [imageData],
            now: Date(timeIntervalSince1970: 1_100)
        )
    }

    func corruptLastByte(in url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        let endOffset = try handle.seekToEnd()
        try handle.seek(toOffset: endOffset - 1)
        let original = try XCTUnwrap(try handle.read(upToCount: 1)?.first)
        try handle.seek(toOffset: endOffset - 1)
        try handle.write(contentsOf: Data([original ^ 0xFF]))
        try handle.close()
    }

    func importRootIsEmpty(descriptor: CanonicalStoreDescriptor) throws -> Bool {
        let importRoot = descriptor.rootDirectory
            .appendingPathComponent("BackupPackageImports", isDirectory: true)
        guard FileManager.default.fileExists(atPath: importRoot.path) else {
            return true
        }
        return try FileManager.default.contentsOfDirectory(atPath: importRoot.path).isEmpty
    }
}
