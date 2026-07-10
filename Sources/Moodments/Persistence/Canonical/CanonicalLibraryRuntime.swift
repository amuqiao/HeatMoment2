import Foundation
import SwiftData

struct CanonicalStoreDescriptor: Sendable, Equatable {
    let rootDirectory: URL
    let databaseURL: URL
    let assetDirectoryURL: URL
    let recoveryPointDirectoryURL: URL

    init(
        rootDirectory: URL,
        databaseFileName: String = "MoodmentsCanonical.sqlite"
    ) {
        self.rootDirectory = rootDirectory
        databaseURL = rootDirectory.appendingPathComponent(databaseFileName)
        assetDirectoryURL = rootDirectory.appendingPathComponent("Assets", isDirectory: true)
        recoveryPointDirectoryURL = rootDirectory.appendingPathComponent(
            "RecoveryPoints",
            isDirectory: true
        )
    }
}

struct CanonicalLibraryRuntime: Sendable {
    let descriptor: CanonicalStoreDescriptor?
    let store: CanonicalStore
    let assetStore: FileAssetStore
    let repository: CanonicalLibraryRepository
    let assetPinStore: CanonicalAssetPinStore
    let recoveryPointStore: CanonicalRecoveryPointStore
    let recoveryPointSnapshotService: CanonicalRecoveryPointSnapshotService
    let assetReachabilityService: CanonicalAssetReachabilityService
    let assetOperationGate: CanonicalAssetOperationGate

    init(descriptor: CanonicalStoreDescriptor) throws {
        try FileManager.default.createDirectory(
            at: descriptor.rootDirectory,
            withIntermediateDirectories: true
        )
        self.descriptor = descriptor
        store = try CanonicalStore(path: descriptor.databaseURL.path)
        assetStore = FileAssetStore(rootDirectory: descriptor.assetDirectoryURL)
        repository = CanonicalLibraryRepository(store: store)
        assetPinStore = CanonicalAssetPinStore(store: store)
        let recoveryPointStore = CanonicalRecoveryPointStore(store: store)
        self.recoveryPointStore = recoveryPointStore
        assetOperationGate = CanonicalAssetOperationGate.shared(
            forAssetRootDirectory: assetStore.rootDirectory
        )
        recoveryPointSnapshotService = CanonicalRecoveryPointSnapshotService(
            store: store,
            recoveryPointStore: recoveryPointStore,
            assetStore: assetStore,
            operationGate: assetOperationGate,
            rootDirectory: descriptor.rootDirectory,
            recoveryPointDirectoryURL: descriptor.recoveryPointDirectoryURL
        )
        assetReachabilityService = CanonicalAssetReachabilityService(
            store: store,
            assetStore: assetStore,
            operationGate: assetOperationGate
        )
    }

    private init(store: CanonicalStore, assetStore: FileAssetStore) {
        descriptor = nil
        self.store = store
        self.assetStore = assetStore
        repository = CanonicalLibraryRepository(store: store)
        assetPinStore = CanonicalAssetPinStore(store: store)
        let recoveryPointStore = CanonicalRecoveryPointStore(store: store)
        self.recoveryPointStore = recoveryPointStore
        let rootDirectory = assetStore.rootDirectory.deletingLastPathComponent()
        assetOperationGate = CanonicalAssetOperationGate.shared(
            forAssetRootDirectory: assetStore.rootDirectory
        )
        recoveryPointSnapshotService = CanonicalRecoveryPointSnapshotService(
            store: store,
            recoveryPointStore: recoveryPointStore,
            assetStore: assetStore,
            operationGate: assetOperationGate,
            rootDirectory: rootDirectory,
            recoveryPointDirectoryURL: rootDirectory.appendingPathComponent(
                "RecoveryPoints",
                isDirectory: true
            )
        )
        assetReachabilityService = CanonicalAssetReachabilityService(
            store: store,
            assetStore: assetStore,
            operationGate: assetOperationGate
        )
    }

    static func makeProduction() throws -> CanonicalLibraryRuntime {
        try CanonicalLibraryRuntime(
            descriptor: CanonicalStoreDescriptor(rootDirectory: applicationSupportDirectory)
        )
    }

    static func makeInMemoryForTests(
        assetDirectoryURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MoodmentsCanonicalAssets-\(UUID().uuidString)", isDirectory: true)
    ) throws -> CanonicalLibraryRuntime {
        try CanonicalLibraryRuntime(
            store: CanonicalStore.makeInMemory(),
            assetStore: FileAssetStore(rootDirectory: assetDirectoryURL)
        )
    }

    @discardableResult
    func importFromSwiftDataIfNeeded(
        modelContainer: ModelContainer,
        importedAt: Date = .now
    ) async throws -> SwiftDataCanonicalImportResult {
        let importer = SwiftDataCanonicalImporter(modelContainer: modelContainer)
        return try await importer.importIfNeeded(
            into: store,
            assetStore: assetStore,
            operationGate: assetOperationGate,
            importedAt: importedAt
        )
    }

    private static var applicationSupportDirectory: URL {
        #if DEBUG
            if let directory = UITestSupport.localBackupApplicationSupportDirectory {
                return
                    directory
                    .appendingPathComponent("Canonical", isDirectory: true)
            }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Canonical", isDirectory: true)
    }
}
